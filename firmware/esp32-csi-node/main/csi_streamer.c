/**
 * Æther CSI Node — ESP32-S3 WiFi CSI Capture & UDP Streamer
 *
 * Captures Channel State Information (CSI) from WiFi frames and
 * streams them to the Æther hub via UDP for real-time processing.
 *
 * Frame format:
 *   [0xAE 0x01]  — magic (2 bytes)
 *   [seq_hi seq_lo] — sequence number (2 bytes, big-endian)
 *   [rssi]       — RSSI value (1 byte, signed)
 *   [rate]       — data rate (1 byte)
 *   [noise_floor] — noise floor (1 byte, signed)
 *   [channel]    — WiFi channel (1 byte)
 *   [csi_len_hi csi_len_lo] — CSI data length (2 bytes)
 *   [csi_data...] — raw CSI amplitude/phase data
 *
 * Build: idf.py build
 * Flash: idf.py -p /dev/ttyACM0 flash monitor
 *
 * Configure via: idf.py menuconfig → "Æther CSI Node Configuration"
 */

#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_system.h"
#include "nvs_flash.h"
#include "lwip/err.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"

#define AETHER_MAGIC_HI  0xAE
#define AETHER_MAGIC_LO  0x01
#define MAX_FRAME_SIZE    1500
#define TAG               "aether-csi"

// Counters
static uint16_t g_seq = 0;
static uint32_t g_frames_sent = 0;
static uint32_t g_frames_dropped = 0;

// UDP socket
static int g_udp_sock = -1;
static struct sockaddr_in g_hub_addr;

// WiFi connected event group
static EventGroupHandle_t g_wifi_event_group;
#define WIFI_CONNECTED_BIT BIT0

/**
 * Build an Æther CSI frame and send via UDP.
 */
static void send_csi_frame(const wifi_csi_info_t *info) {
    if (g_udp_sock < 0 || !info || !info->buf) {
        g_frames_dropped++;
        return;
    }

    uint16_t csi_len = info->len;
    size_t frame_len = 10 + csi_len; // header(10) + csi_data

    if (frame_len > MAX_FRAME_SIZE) {
        g_frames_dropped++;
        return;
    }

    uint8_t frame[MAX_FRAME_SIZE];

    // Header
    frame[0] = AETHER_MAGIC_HI;
    frame[1] = AETHER_MAGIC_LO;
    frame[2] = (g_seq >> 8) & 0xFF;
    frame[3] = g_seq & 0xFF;
    frame[4] = (uint8_t)info->rx_ctrl.rssi;
    frame[5] = (uint8_t)info->rx_ctrl.rate;
    frame[6] = (uint8_t)info->rx_ctrl.noise_floor;
    frame[7] = (uint8_t)info->rx_ctrl.channel;
    frame[8] = (csi_len >> 8) & 0xFF;
    frame[9] = csi_len & 0xFF;

    // CSI data
    memcpy(frame + 10, info->buf, csi_len);

    int sent = sendto(g_udp_sock, frame, frame_len, 0,
                      (struct sockaddr *)&g_hub_addr, sizeof(g_hub_addr));
    if (sent > 0) {
        g_seq++;
        g_frames_sent++;
    } else {
        g_frames_dropped++;
    }
}

/**
 * CSI callback — invoked by ESP32 WiFi driver for each received frame.
 */
static void csi_rx_callback(void *ctx, wifi_csi_info_t *info) {
    send_csi_frame(info);
}

/**
 * WiFi event handler.
 */
static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                                int32_t event_id, void *event_data) {
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        ESP_LOGW(TAG, "WiFi disconnected, reconnecting...");
        xEventGroupClearBits(g_wifi_event_group, WIFI_CONNECTED_BIT);
        esp_wifi_connect();
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
        ESP_LOGI(TAG, "Got IP: " IPSTR, IP2STR(&event->ip_info.ip));
        xEventGroupSetBits(g_wifi_event_group, WIFI_CONNECTED_BIT);
    }
}

/**
 * Initialize WiFi in station mode.
 */
static void wifi_init(void) {
    g_wifi_event_group = xEventGroupCreate();

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL, NULL));

    wifi_config_t wifi_config = {
        .sta = {
            .ssid = CONFIG_AETHER_WIFI_SSID,
            .password = CONFIG_AETHER_WIFI_PASSWORD,
            .threshold.authmode = WIFI_AUTH_WPA2_PSK,
        },
    };

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());

    ESP_LOGI(TAG, "WiFi init complete, connecting to %s", CONFIG_AETHER_WIFI_SSID);

    // Wait for connection
    xEventGroupWaitBits(g_wifi_event_group, WIFI_CONNECTED_BIT,
                        pdFALSE, pdTRUE, portMAX_DELAY);
}

/**
 * Initialize UDP socket to Æther hub.
 */
static void udp_init(void) {
    g_udp_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (g_udp_sock < 0) {
        ESP_LOGE(TAG, "Failed to create UDP socket");
        return;
    }

    memset(&g_hub_addr, 0, sizeof(g_hub_addr));
    g_hub_addr.sin_family = AF_INET;
    g_hub_addr.sin_port = htons(CONFIG_AETHER_HUB_PORT);
    inet_aton(CONFIG_AETHER_HUB_IP, &g_hub_addr.sin_addr);

    ESP_LOGI(TAG, "UDP socket ready → %s:%d",
             CONFIG_AETHER_HUB_IP, CONFIG_AETHER_HUB_PORT);
}

/**
 * Enable CSI collection.
 */
static void csi_init(void) {
    wifi_csi_config_t csi_config = {
        .lltf_en = true,           // Legacy Long Training Field
        .htltf_en = true,          // HT Long Training Field
        .stbc_htltf2_en = true,    // Space-Time Block Coding
        .ltf_merge_en = true,      // Merge LTF for better SNR
        .channel_filter_en = false, // Don't filter — send raw CSI
        .manu_scale = false,       // Automatic scaling
    };

    ESP_ERROR_CHECK(esp_wifi_set_csi_config(&csi_config));
    ESP_ERROR_CHECK(esp_wifi_set_csi_rx_cb(csi_rx_callback, NULL));
    ESP_ERROR_CHECK(esp_wifi_set_csi(true));

    ESP_LOGI(TAG, "CSI capture enabled (LLTF + HTLTF + STBC)");
}

/**
 * Stats reporting task.
 */
static void stats_task(void *pvParameters) {
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(10000));
        ESP_LOGI(TAG, "Stats: sent=%lu dropped=%lu seq=%u",
                 g_frames_sent, g_frames_dropped, g_seq);
    }
}

/**
 * Main entry point.
 */
void app_main(void) {
    ESP_LOGI(TAG, "╔══════════════════════════════════════╗");
    ESP_LOGI(TAG, "║   Æther CSI Node v0.1.0              ║");
    ESP_LOGI(TAG, "║   Ambient RF Perception System       ║");
    ESP_LOGI(TAG, "╚══════════════════════════════════════╝");

    // NVS init (required for WiFi)
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ESP_ERROR_CHECK(nvs_flash_init());
    }

    // Init subsystems
    wifi_init();
    udp_init();
    csi_init();

    // Start stats reporter
    xTaskCreate(stats_task, "aether_stats", 2048, NULL, 5, NULL);

    ESP_LOGI(TAG, "Streaming CSI to %s:%d — Æther is perceiving.",
             CONFIG_AETHER_HUB_IP, CONFIG_AETHER_HUB_PORT);
}
