import aether/core/types.{
  type PersonId, type SensorId, type ThroughWallTarget, type Vec3,
  type VitalsAlertKind, type ZoneId, type ZoneOccupancy,
}
import gleam/option.{type Option}

pub type SkeletonGraph {
  Coco17
  Halpe26
  CustomTopology(edges: List(#(Int, Int)), names: List(String))
}

pub type Keypoint {
  Keypoint(
    id: Int,
    name: String,
    x: Float,
    y: Float,
    z: Float,
    confidence: Float,
    velocity: Option(Vec3),
  )
}

pub type Perception {
  Pose(keypoints: List(Keypoint), skeleton: SkeletonGraph, confidence: Float)
  Vitals(
    heart_bpm: Float,
    breath_bpm: Float,
    hrv: Option(Float),
    confidence: Float,
  )
  Presence(zones: List(ZoneOccupancy), total_occupants: Int)
  Location(position: Vec3, accuracy_m: Float, velocity: Option(Vec3))
  Activity(label: String, confidence: Float, duration_ms: Int)
  ThroughWall(targets: List(ThroughWallTarget))
  FreeformPerception(kind: String, data: String)
}

pub type Event {
  PersonEntered(person: PersonId, zone: ZoneId)
  PersonLeft(person: PersonId, zone: ZoneId)
  FallDetected(person: PersonId, confidence: Float)
  VitalsAlert(person: PersonId, kind: VitalsAlertKind)
  SensorOffline(sensor: SensorId)
  SensorRecovered(sensor: SensorId)
}
