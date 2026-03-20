//! Activity Decoder — Classification head
//!
//! Recognizes human activities from temporal CSI patterns.
//! Activities: idle, walking, sitting_down, standing_up, waving, falling.

use crate::model::InferenceResult;
use serde_json::json;

const ACTIVITIES: [&str; 6] = [
    "idle",
    "walking",
    "sitting_down",
    "standing_up",
    "waving",
    "falling",
];

pub fn infer(embedding: &[f64]) -> InferenceResult {
    let n = embedding.len() as f64;
    if n < 1.0 {
        return InferenceResult {
            task: "activity".to_string(),
            data: json!({"label": "unknown", "probabilities": {}}),
            confidence: 0.0,
        };
    }

    // Compute features for classification
    let mean: f64 = embedding.iter().sum::<f64>() / n;
    let variance: f64 = embedding.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / n;
    let max_val: f64 = embedding.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    let min_val: f64 = embedding.iter().cloned().fold(f64::INFINITY, f64::min);
    let range = max_val - min_val;

    // Simple heuristic classifier based on signal dynamics
    // Real implementation: trained classification head
    let (label, confidence) = if variance < 0.001 {
        ("idle", 0.9)
    } else if range > 5.0 {
        ("falling", 0.7)
    } else if variance > 1.0 {
        ("walking", 0.75)
    } else if mean > 0.5 {
        ("standing_up", 0.6)
    } else if mean < -0.5 {
        ("sitting_down", 0.6)
    } else {
        ("waving", 0.5)
    };

    InferenceResult {
        task: "activity".to_string(),
        data: json!({
            "label": label,
            "duration_ms": 0
        }),
        confidence,
    }
}
