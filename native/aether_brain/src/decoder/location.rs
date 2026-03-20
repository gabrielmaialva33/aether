//! Location Decoder — 3D positioning
//!
//! Estimates position from CSI phase/AoA features.
//! Future: geometry-aware decoder modeling RF propagation physics.

use crate::model::InferenceResult;
use serde_json::json;

pub fn infer(embedding: &[f64]) -> InferenceResult {
    let n = embedding.len();
    if n < 3 {
        return InferenceResult {
            task: "location".to_string(),
            data: json!({"x": 0.0, "y": 0.0, "z": 0.0, "accuracy_m": 999.0}),
            confidence: 0.0,
        };
    }

    // Extract position estimate from embedding
    // Real implementation: trained regression head with Fresnel zone modeling
    let x = embedding[0] * 2.5 + 2.5; // map to [0, 5] meters
    let y = embedding[1] * 2.0 + 2.0; // map to [0, 4] meters
    let z = embedding[2].abs().min(3.0); // height [0, 3] meters

    // Accuracy from embedding confidence
    let energy: f64 = embedding.iter().map(|v| v * v).sum::<f64>();
    let accuracy = (2.0 / (energy.sqrt() + 1.0)).max(0.1); // meters

    let confidence = (1.0 - accuracy / 5.0).max(0.1).min(0.95);

    InferenceResult {
        task: "location".to_string(),
        data: json!({
            "x": (x * 100.0).round() / 100.0,
            "y": (y * 100.0).round() / 100.0,
            "z": (z * 100.0).round() / 100.0,
            "accuracy_m": (accuracy * 100.0).round() / 100.0
        }),
        confidence,
    }
}
