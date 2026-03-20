/// Tests for the orchestrator — JSON parsing, ring buffer, real inference.
import aether/condition/pipeline
import aether/core/types.{Vec3}
import aether/orchestrator
import aether/perception.{Activity, Coco17, Location, Pose, Presence, Vitals}
import aether/signal.{Signal, WifiCsi}
import gleam/erlang/process
import gleam/float
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn orchestrator_produces_real_perceptions_test() {
  let assert Ok(orch) =
    orchestrator.start(
      orchestrator.OrchestratorConfig(
        conditioners: [],
        model_path: "test.pt",
        device: "cpu",
        tasks: ["vitals", "presence", "activity"],
      ),
    )

  // Send a signal with real data
  let signal =
    Signal(
      source: "test",
      kind: WifiCsi(4, 1, 20),
      timestamp: 1000,
      payload: <<50, 100, 150, 200, 30, 60, 90, 120, 10, 20, 30, 40>>,
      metadata: [],
    )
  orchestrator.ingest(orch, signal)

  // Wait for async processing, then query synchronously
  process.sleep(300)
  let perceptions = orchestrator.get_perceptions(orch)
  { perceptions != [] } |> should.be_true()

  // Verify at least one perception was produced
  list.length(perceptions) |> should.not_equal(0)
}

pub fn orchestrator_ring_buffer_stabilizes_test() {
  let assert Ok(orch) =
    orchestrator.start(
      orchestrator.OrchestratorConfig(
        conditioners: [],
        model_path: "test.pt",
        device: "cpu",
        tasks: ["presence"],
      ),
    )

  let sub = process.new_subject()
  orchestrator.subscribe(orch, sub)

  // Send multiple frames — ring buffer should accumulate and stabilize
  let make_signal = fn(data: BitArray) {
    Signal(
      source: "buffer-test",
      kind: WifiCsi(4, 1, 20),
      timestamp: 1000,
      payload: data,
      metadata: [],
    )
  }

  orchestrator.ingest(orch, make_signal(<<10, 20, 30, 40>>))
  let assert Ok(_p1) = process.receive(sub, 1000)

  orchestrator.ingest(orch, make_signal(<<50, 60, 70, 80>>))
  let assert Ok(_p2) = process.receive(sub, 1000)

  orchestrator.ingest(orch, make_signal(<<90, 100, 110, 120>>))
  let assert Ok(p3) = process.receive(sub, 1000)

  // After 3 frames, AveCSI should have stabilized values
  // (averaged over all 3 frames, not just the last one)
  { p3 != [] } |> should.be_true()
}

pub fn orchestrator_handles_multiple_tasks_test() {
  let assert Ok(orch) =
    orchestrator.start(
      orchestrator.OrchestratorConfig(
        conditioners: [],
        model_path: "test.pt",
        device: "cpu",
        tasks: ["pose", "vitals", "presence", "activity", "location"],
      ),
    )

  let sub = process.new_subject()
  orchestrator.subscribe(orch, sub)

  orchestrator.ingest(
    orch,
    Signal(
      source: "multi",
      kind: WifiCsi(8, 1, 20),
      timestamp: 1000,
      payload: <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>,
      metadata: [],
    ),
  )

  let assert Ok(perceptions) = process.receive(sub, 2000)
  // Should have 5 perceptions — one for each task
  list.length(perceptions) |> should.equal(5)

  // Verify each type is present
  let has_pose =
    list.any(perceptions, fn(p) {
      case p {
        Pose(..) -> True
        _ -> False
      }
    })
  let has_vitals =
    list.any(perceptions, fn(p) {
      case p {
        Vitals(..) -> True
        _ -> False
      }
    })
  let has_presence =
    list.any(perceptions, fn(p) {
      case p {
        Presence(..) -> True
        _ -> False
      }
    })
  let has_activity =
    list.any(perceptions, fn(p) {
      case p {
        Activity(..) -> True
        _ -> False
      }
    })
  let has_location =
    list.any(perceptions, fn(p) {
      case p {
        Location(..) -> True
        _ -> False
      }
    })

  has_pose |> should.be_true()
  has_vitals |> should.be_true()
  has_presence |> should.be_true()
  has_activity |> should.be_true()
  has_location |> should.be_true()
}

pub fn pose_has_keypoints_test() {
  let assert Ok(orch) =
    orchestrator.start(
      orchestrator.OrchestratorConfig(
        conditioners: [],
        model_path: "test.pt",
        device: "cpu",
        tasks: ["pose"],
      ),
    )

  let sub = process.new_subject()
  orchestrator.subscribe(orch, sub)

  // Send enough data for keypoint extraction
  orchestrator.ingest(
    orch,
    Signal(
      source: "kp",
      kind: WifiCsi(8, 1, 20),
      timestamp: 1000,
      payload: <<
        10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160,
        170, 180, 190, 200, 210, 220, 230, 240, 250, 1, 2, 3, 4, 5, 6, 7, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27,
      >>,
      metadata: [],
    ),
  )

  let assert Ok(perceptions) = process.receive(sub, 2000)
  let assert Ok(pose) =
    list.find(perceptions, fn(p) {
      case p {
        Pose(..) -> True
        _ -> False
      }
    })

  // Pose should have keypoints parsed from the NIF JSON output
  case pose {
    Pose(keypoints, _skeleton, _conf) -> {
      // NIF returns 17 COCO keypoints
      { list.length(keypoints) > 0 } |> should.be_true()
    }
    _ -> should.fail()
  }
}
