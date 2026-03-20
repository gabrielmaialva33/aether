import aether/core/types.{Vec3}
import aether/perception.{Coco17, Keypoint, Pose, Vitals}
import aether/serve/codec
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn encode_pose_test() {
  let pose =
    Pose(
      keypoints: [
        Keypoint(0, "nose", 2.3, 1.1, 0.9, 0.95, Some(Vec3(0.1, 0.0, 0.0))),
      ],
      skeleton: Coco17,
      confidence: 0.92,
    )

  let json_str = codec.encode_perception(pose) |> json.to_string()
  json_str |> should.not_equal("")
  string.contains(json_str, "\"type\":\"pose\"") |> should.be_true()
  string.contains(json_str, "\"nose\"") |> should.be_true()
}

pub fn encode_vitals_test() {
  let vitals =
    Vitals(heart_bpm: 72.3, breath_bpm: 16.1, hrv: Some(45.2), confidence: 0.88)
  let json_str = codec.encode_perception(vitals) |> json.to_string()
  string.contains(json_str, "\"heart_bpm\"") |> should.be_true()
  string.contains(json_str, "\"vitals\"") |> should.be_true()
}

pub fn encode_vitals_no_hrv_test() {
  let vitals =
    Vitals(heart_bpm: 60.0, breath_bpm: 14.0, hrv: None, confidence: 0.9)
  let json_str = codec.encode_perception(vitals) |> json.to_string()
  string.contains(json_str, "null") |> should.be_true()
}
