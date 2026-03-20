//! FFI bindings to aether_brain Rust NIF.
//! Foundation model inference on GPU/CPU.

import gleam/dynamic.{type Dynamic}

/// Load a foundation model from checkpoint.
/// device: "cuda:0" or "cpu"
@external(erlang, "aether_brain_nif", "load_model")
pub fn load_model(path: String, device: String) -> Dynamic

/// Run multi-task inference on fused embedding.
/// Returns JSON string with perception results.
@external(erlang, "aether_brain_nif", "foundation_infer")
pub fn foundation_infer(
  model: Dynamic,
  embedding: List(Float),
  tasks: List(String),
) -> String

/// Cross-modal attention fusion.
/// Merges embeddings from multiple sensor modalities.
@external(erlang, "aether_brain_nif", "cross_modal_fuse")
pub fn cross_modal_fuse(
  embeddings: List(List(Float)),
  modality_ids: List(Int),
) -> List(Float)

/// Get model metadata as JSON.
@external(erlang, "aether_brain_nif", "model_info")
pub fn model_info(model: Dynamic) -> String

/// Check if the brain NIF is loaded.
@external(erlang, "aether_brain_nif", "is_loaded")
pub fn is_loaded() -> Bool
