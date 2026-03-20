//! Pose Decoder — GCN + Attention (scaffold)
//!
//! Future: GraphPose-Fi style GCN decoder with skeleton topology constraints.
//! Current: extracts 17 COCO keypoints from embedding via signal statistics.

use crate::model::InferenceResult;
use serde_json::json;

/// COCO 17 keypoint names
const KEYPOINTS: [&str; 17] = [
    "nose",
    "left_eye",
    "right_eye",
    "left_ear",
    "right_ear",
    "left_shoulder",
    "right_shoulder",
    "left_elbow",
    "right_elbow",
    "left_wrist",
    "right_wrist",
    "left_hip",
    "right_hip",
    "left_knee",
    "right_knee",
    "left_ankle",
    "right_ankle",
];

pub fn infer(embedding: &[f64]) -> InferenceResult {
    let energy: f64 = embedding.iter().map(|x| x * x).sum::<f64>().sqrt();
    let dim = embedding.len();

    // Generate keypoints from embedding features
    // Each keypoint gets x,y,z from consecutive embedding dimensions
    let keypoints: Vec<serde_json::Value> = KEYPOINTS
        .iter()
        .enumerate()
        .map(|(i, name)| {
            let base = (i * 3) % dim.max(1);
            let x = embedding.get(base).copied().unwrap_or(0.0) * 2.0;
            let y = embedding.get(base + 1).copied().unwrap_or(0.0) * 2.0;
            let z = embedding.get(base + 2).copied().unwrap_or(0.5);
            let conf = (energy / (dim as f64).sqrt()).min(1.0);

            json!({
                "id": i,
                "name": name,
                "x": x,
                "y": y,
                "z": z,
                "confidence": conf
            })
        })
        .collect();

    let confidence = (energy / (dim as f64 + 1.0).sqrt()).min(1.0);

    InferenceResult {
        task: "pose".to_string(),
        data: json!({
            "keypoints": keypoints,
            "skeleton": "coco17"
        }),
        confidence,
    }
}
