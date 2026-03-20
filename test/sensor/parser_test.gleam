import aether/sensor/parser
import aether/signal.{WifiCsi}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn parse_wifi_csi_frame_test() {
  let frame = <<
    0xAE, 0x01, 0x00, 0x01, 63, 128, 0, 0, 64, 0, 0, 0, 64, 64, 0, 0, 64, 128, 0,
    0, 64, 160, 0, 0, 64, 192, 0, 0,
  >>

  let kind = WifiCsi(subcarriers: 2, antennas: 3, bandwidth: 20)
  let result = parser.parse_csi_frame(frame, kind)
  result |> should.be_ok()
}

pub fn parse_invalid_magic_test() {
  let frame = <<0xFF, 0xFF, 0x00, 0x01>>
  let kind = WifiCsi(subcarriers: 2, antennas: 3, bandwidth: 20)
  let result = parser.parse_csi_frame(frame, kind)
  result |> should.be_error()
}
