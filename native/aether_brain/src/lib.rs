//! Æther Brain NIF — Foundation Model Inference
//!
//! GPU-accelerated (or CPU fallback) ML inference for RF perception.
//! All inference functions use DirtyCpu scheduler to avoid blocking BEAM.

mod model;
pub mod decoder;

use model::Model;
use rustler::{Env, NifResult, ResourceArc, Term};
use std::sync::Mutex;

/// Opaque model reference held in BEAM process memory.
pub struct ModelRef {
    inner: Mutex<Model>,
}

fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(ModelRef, env);
    true
}

/// Load a foundation model from checkpoint path.
#[rustler::nif(schedule = "DirtyCpu")]
fn load_model(path: String, device: String) -> NifResult<ResourceArc<ModelRef>> {
    let model = Model::load(&path, &device).map_err(|e| {
        rustler::Error::Term(Box::new(format!("model load error: {}", e)))
    })?;
    Ok(ResourceArc::new(ModelRef {
        inner: Mutex::new(model),
    }))
}

/// Run foundation model inference on fused embedding.
/// Returns JSON-encoded list of perception results.
#[rustler::nif(schedule = "DirtyCpu")]
fn foundation_infer(
    model: ResourceArc<ModelRef>,
    embedding: Vec<f64>,
    tasks: Vec<String>,
) -> NifResult<String> {
    let guard = model
        .inner
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new("model lock poisoned".to_string())))?;
    let results = guard.infer(&embedding, &tasks);
    let json = serde_json::to_string(&results)
        .map_err(|e| rustler::Error::Term(Box::new(format!("json error: {}", e))))?;
    Ok(json)
}

/// Cross-modal attention fusion: merge embeddings from multiple sensors.
#[rustler::nif(schedule = "DirtyCpu")]
fn cross_modal_fuse(
    embeddings: Vec<Vec<f64>>,
    modality_ids: Vec<u32>,
) -> NifResult<Vec<f64>> {
    if embeddings.is_empty() {
        return Ok(vec![]);
    }
    Ok(model::cross_modal_attention(&embeddings, &modality_ids))
}

/// Get model info as JSON.
#[rustler::nif]
fn model_info(model: ResourceArc<ModelRef>) -> NifResult<String> {
    let guard = model
        .inner
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new("model lock poisoned".to_string())))?;
    let info = guard.info();
    let json = serde_json::to_string(&info)
        .map_err(|e| rustler::Error::Term(Box::new(format!("json error: {}", e))))?;
    Ok(json)
}

rustler::init!("aether_brain_nif", load = on_load);
