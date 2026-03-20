//! Presence Decoder — Classification head
//!
//! Detects number of occupants and zone presence from CSI patterns.
//! CSI amplitude variance increases with number of moving bodies.

use crate::model::InferenceResult;
use serde_json::json;

pub fn infer(embedding: &[f64]) -> InferenceResult {
    let n = embedding.len() as f64;
    if n < 1.0 {
        return InferenceResult {
            task: "presence".to_string(),
            data: json!({"occupied": false, "occupant_count": 0}),
            confidence: 0.0,
        };
    }

    // Energy-based presence detection
    let energy: f64 = embedding.iter().map(|x| x * x).sum::<f64>();
    let mean_energy = energy / n;

    // Variance indicates movement
    let mean: f64 = embedding.iter().sum::<f64>() / n;
    let variance: f64 = embedding.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / n;

    // Threshold: energy above baseline indicates presence
    let occupied = mean_energy > 0.01;

    // Rough occupant estimation: more variance = more people
    let occupant_count = if !occupied {
        0
    } else {
        ((variance.sqrt() * 5.0).round() as u32).max(1).min(10)
    };

    let confidence = if occupied {
        (mean_energy.sqrt().min(1.0) * 0.9 + 0.1).min(0.99)
    } else {
        0.95 // High confidence in "empty"
    };

    InferenceResult {
        task: "presence".to_string(),
        data: json!({
            "occupied": occupied,
            "occupant_count": occupant_count
        }),
        confidence,
    }
}
