import aether/perception.{
  type Event, type Keypoint, type Perception, Activity, Coco17, CustomTopology,
  FallDetected, FreeformPerception, Halpe26, Location, PersonEntered, PersonLeft,
  Pose, Presence, SensorOffline, SensorRecovered, ThroughWall, Vitals,
  VitalsAlert,
}
import gleam/json.{type Json}
import gleam/option.{None, Some}

pub fn encode_perception(p: Perception) -> Json {
  case p {
    Pose(keypoints, skeleton, confidence) ->
      json.object([
        #("type", json.string("pose")),
        #("keypoints", json.array(keypoints, encode_keypoint)),
        #("skeleton", json.string(skeleton_name(skeleton))),
        #("confidence", json.float(confidence)),
      ])
    Vitals(heart, breath, hrv, confidence) ->
      json.object([
        #("type", json.string("vitals")),
        #("heart_bpm", json.float(heart)),
        #("breath_bpm", json.float(breath)),
        #("hrv", case hrv {
          Some(v) -> json.float(v)
          None -> json.null()
        }),
        #("confidence", json.float(confidence)),
      ])
    Presence(_zones, total) ->
      json.object([
        #("type", json.string("presence")),
        #("total_occupants", json.int(total)),
      ])
    Location(pos, acc, _vel) ->
      json.object([
        #("type", json.string("location")),
        #("x", json.float(pos.x)),
        #("y", json.float(pos.y)),
        #("z", json.float(pos.z)),
        #("accuracy_m", json.float(acc)),
      ])
    Activity(label, confidence, duration) ->
      json.object([
        #("type", json.string("activity")),
        #("label", json.string(label)),
        #("confidence", json.float(confidence)),
        #("duration_ms", json.int(duration)),
      ])
    ThroughWall(_targets) ->
      json.object([#("type", json.string("through_wall"))])
    FreeformPerception(kind, _data) ->
      json.object([
        #("type", json.string("freeform")),
        #("kind", json.string(kind)),
      ])
  }
}

fn encode_keypoint(kp: Keypoint) -> Json {
  json.object([
    #("id", json.int(kp.id)),
    #("name", json.string(kp.name)),
    #("x", json.float(kp.x)),
    #("y", json.float(kp.y)),
    #("z", json.float(kp.z)),
    #("confidence", json.float(kp.confidence)),
  ])
}

fn skeleton_name(s) -> String {
  case s {
    Coco17 -> "coco17"
    Halpe26 -> "halpe26"
    CustomTopology(_, _) -> "custom"
  }
}

pub fn encode_event(e: Event) -> Json {
  case e {
    PersonEntered(person, zone) ->
      json.object([
        #("event", json.string("person_entered")),
        #("person", json.string(person)),
        #("zone", json.string(zone)),
      ])
    PersonLeft(person, zone) ->
      json.object([
        #("event", json.string("person_left")),
        #("person", json.string(person)),
        #("zone", json.string(zone)),
      ])
    FallDetected(person, confidence) ->
      json.object([
        #("event", json.string("fall_detected")),
        #("person", json.string(person)),
        #("confidence", json.float(confidence)),
      ])
    SensorOffline(sensor) ->
      json.object([
        #("event", json.string("sensor_offline")),
        #("sensor", json.string(sensor)),
      ])
    SensorRecovered(sensor) ->
      json.object([
        #("event", json.string("sensor_recovered")),
        #("sensor", json.string(sensor)),
      ])
    VitalsAlert(person, _kind) ->
      json.object([
        #("event", json.string("vitals_alert")),
        #("person", json.string(person)),
      ])
  }
}
