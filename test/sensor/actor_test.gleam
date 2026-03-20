import aether/sensor/actor as sensor_actor
import aether/signal.{WifiCsi}
import gleam/erlang/process
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn sensor_actor_receives_frame_test() {
  let subscriber = process.new_subject()
  let assert Ok(sensor) =
    sensor_actor.start_with_subject(
      "test-sensor",
      WifiCsi(subcarriers: 2, antennas: 3, bandwidth: 20),
      subscriber,
    )

  let frame = <<
    0xAE, 0x01, 0x00, 0x01, 63, 128, 0, 0, 64, 0, 0, 0, 64, 64, 0, 0, 64, 128, 0,
    0, 64, 160, 0, 0, 64, 192, 0, 0,
  >>
  sensor_actor.inject_frame(sensor, frame)

  let assert Ok(signal) = process.receive(subscriber, 1000)
  signal.source |> should.equal("test-sensor")
}

pub fn sensor_actor_counts_frames_test() {
  let subscriber = process.new_subject()
  let assert Ok(sensor) =
    sensor_actor.start_with_subject(
      "counter-test",
      WifiCsi(subcarriers: 2, antennas: 3, bandwidth: 20),
      subscriber,
    )

  let frame = <<0xAE, 0x01, 0x00, 0x01, 1, 2, 3, 4>>
  sensor_actor.inject_frame(sensor, frame)
  sensor_actor.inject_frame(sensor, frame)

  let _ = process.receive(subscriber, 100)
  let _ = process.receive(subscriber, 100)

  let stats = sensor_actor.get_stats(sensor)
  stats.frames_received |> should.equal(2)
}

pub fn sensor_actor_counts_parse_errors_test() {
  let subscriber = process.new_subject()
  let assert Ok(sensor) =
    sensor_actor.start_with_subject(
      "error-test",
      WifiCsi(subcarriers: 2, antennas: 3, bandwidth: 20),
      subscriber,
    )

  sensor_actor.inject_frame(sensor, <<0xFF, 0xFF, 0x00, 0x01>>)
  process.sleep(50)

  let stats = sensor_actor.get_stats(sensor)
  stats.parse_errors |> should.equal(1)
}
