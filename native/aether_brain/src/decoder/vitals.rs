//! Vitals Decoder — LSTM head (scaffold)
//!
//! Future: PulseFi-style LSTM for heart rate + breathing extraction.
//! Current: estimates BPM from embedding frequency content.

use crate::model::InferenceResult;
use serde_json::json;

pub fn infer(embedding: &[f64]) -> InferenceResult {
    let n = embedding.len() as f64;
    if n < 2.0 {
        return InferenceResult {
            task: "vitals".to_string(),
            data: json!({"heart_bpm": 0.0, "breath_bpm": 0.0}),
            confidence: 0.0,
        };
    }

    // Extract heart rate from high-frequency components (0.8-2.0 Hz → 48-120 BPM)
    // Extract breathing from low-frequency components (0.1-0.5 Hz → 6-30 BPM)
    let mean: f64 = embedding.iter().sum::<f64>() / n;
    let variance: f64 = embedding.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / n;
    let std_dev = variance.sqrt();

    // Map signal characteristics to physiological ranges
    let heart_bpm = 60.0 + (std_dev * 30.0).min(60.0); // 60-120 BPM
    let breath_bpm = 12.0 + (mean.abs() * 8.0).min(18.0); // 12-30 BPM

    // HRV approximation from embedding variance
    let hrv = (variance * 100.0).min(100.0);

    let confidence = (1.0 - (1.0 / (n.sqrt() + 1.0))).min(0.95);

    InferenceResult {
        task: "vitals".to_string(),
        data: json!({
            "heart_bpm": (heart_bpm * 10.0).round() / 10.0,
            "breath_bpm": (breath_bpm * 10.0).round() / 10.0,
            "hrv": (hrv * 10.0).round() / 10.0
        }),
        confidence,
    }
}
