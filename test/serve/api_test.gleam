/// API server integration test.
/// Starts the full stack and hits HTTP endpoints.
import aether/orchestrator
import aether/serve/api
import aether/signal.{Signal, WifiCsi}
import gleam/erlang/process
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn health_endpoint_test() {
  // 1. Start orchestrator
  let assert Ok(orch) =
    orchestrator.start(
      orchestrator.OrchestratorConfig(
        conditioners: [],
        model_path: "test.pt",
        device: "cpu",
        tasks: ["presence"],
      ),
    )

  // 2. Start API on random high port
  let port = 18_901
  let assert Ok(_) = api.start(port, orch)

  // 3. Small delay for server to bind
  process.sleep(100)

  // 4. Hit health endpoint via Erlang httpc
  let assert Ok(body) =
    http_get("http://127.0.0.1:" <> int_to_str(port) <> "/api/health")
  string.contains(body, "\"status\":\"ok\"") |> should.be_true()
  string.contains(body, "\"aether\"") |> should.be_true()
}

pub fn perceptions_endpoint_test() {
  let assert Ok(orch) =
    orchestrator.start(
      orchestrator.OrchestratorConfig(
        conditioners: [],
        model_path: "test.pt",
        device: "cpu",
        tasks: ["presence"],
      ),
    )

  let port = 18_902
  let assert Ok(_) = api.start(port, orch)
  process.sleep(100)

  // Ingest a signal first
  let signal =
    Signal(
      source: "test",
      kind: WifiCsi(4, 1, 20),
      timestamp: 1000,
      payload: <<1, 2, 3, 4, 5, 6, 7, 8>>,
      metadata: [],
    )
  orchestrator.ingest(orch, signal)
  process.sleep(100)

  let assert Ok(body) =
    http_get("http://127.0.0.1:" <> int_to_str(port) <> "/api/perceptions")
  string.contains(body, "\"perceptions\"") |> should.be_true()
}

pub fn not_found_test() {
  let assert Ok(orch) =
    orchestrator.start(
      orchestrator.OrchestratorConfig(
        conditioners: [],
        model_path: "test.pt",
        device: "cpu",
        tasks: [],
      ),
    )

  let port = 18_903
  let assert Ok(_) = api.start(port, orch)
  process.sleep(100)

  let assert Ok(body) =
    http_get("http://127.0.0.1:" <> int_to_str(port) <> "/api/nonexistent")
  string.contains(body, "\"not found\"") |> should.be_true()
}

// --- Erlang FFI for HTTP client ---

@external(erlang, "aether_http_test_ffi", "http_get")
fn http_get(url: String) -> Result(String, String)

@external(erlang, "erlang", "integer_to_binary")
fn int_to_str(n: Int) -> String
