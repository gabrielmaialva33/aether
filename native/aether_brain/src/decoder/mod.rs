//! Multi-task decoder heads for the foundation model.
//!
//! Each decoder takes the fused embedding from the encoder
//! and produces task-specific output.
//!
//! Current: heuristic decoders (signal statistics → perception).
//! Future: GCN + attention (pose), LSTM (vitals), classification (presence/activity).

pub mod activity;
pub mod location;
pub mod pose;
pub mod presence;
pub mod vitals;
