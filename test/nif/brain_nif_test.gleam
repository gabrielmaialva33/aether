import aether/nif/brain as nif
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn brain_nif_is_loaded_test() {
  nif.is_loaded() |> should.be_true()
}

pub fn cross_modal_fuse_test() {
  let embeddings = [
    [1.0, 0.0, 0.0, 0.0],
    [0.0, 1.0, 0.0, 0.0],
    [0.0, 0.0, 1.0, 0.0],
  ]
  let modality_ids = [0, 1, 2]

  let fused = nif.cross_modal_fuse(embeddings, modality_ids)
  fused |> list.length() |> should.equal(4)
}

pub fn cross_modal_fuse_empty_test() {
  let fused = nif.cross_modal_fuse([], [])
  fused |> list.length() |> should.equal(0)
}

pub fn foundation_infer_pose_test() {
  let model = nif.load_model("test.pt", "cpu")
  let embedding = list.repeat(1.0, 128)
  let result = nif.foundation_infer(model, embedding, ["pose"])

  // Should return valid JSON with pose data
  string.contains(result, "\"task\":\"pose\"") |> should.be_true()
  string.contains(result, "\"keypoints\"") |> should.be_true()
}

pub fn foundation_infer_vitals_test() {
  let model = nif.load_model("test.pt", "cpu")
  let embedding = list.repeat(0.5, 64)
  let result = nif.foundation_infer(model, embedding, ["vitals"])

  string.contains(result, "\"heart_bpm\"") |> should.be_true()
  string.contains(result, "\"breath_bpm\"") |> should.be_true()
}

pub fn foundation_infer_multi_task_test() {
  let model = nif.load_model("test.pt", "cpu")
  let embedding = list.repeat(1.0, 128)
  let result =
    nif.foundation_infer(model, embedding, [
      "pose", "vitals", "presence", "activity", "location",
    ])

  // All 5 tasks should be in the result
  string.contains(result, "\"pose\"") |> should.be_true()
  string.contains(result, "\"vitals\"") |> should.be_true()
  string.contains(result, "\"presence\"") |> should.be_true()
  string.contains(result, "\"activity\"") |> should.be_true()
  string.contains(result, "\"location\"") |> should.be_true()
}

pub fn model_info_test() {
  let model = nif.load_model("test.pt", "cpu")
  let info = nif.model_info(model)

  string.contains(info, "\"device\":\"cpu\"") |> should.be_true()
  string.contains(info, "\"version\"") |> should.be_true()
}
