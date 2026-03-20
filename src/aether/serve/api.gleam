/// Æther HTTP API Server
///
/// REST endpoints:
///   GET  /api/health              → system health
///   GET  /api/perceptions         → latest perceptions
///   GET  /api/sensors             → sensor status
import aether/orchestrator.{type OrchestratorMsg}
import aether/serve/codec
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import mist.{type Connection, type ResponseData}

/// Start the HTTP server on the given port.
pub fn start(
  port: Int,
  orchestrator: Subject(OrchestratorMsg),
) -> Result(Nil, String) {
  let handler = fn(req: Request(Connection)) -> Response(ResponseData) {
    handle_request(req, orchestrator)
  }

  case mist.new(handler) |> mist.port(port) |> mist.start() {
    Ok(_) -> Ok(Nil)
    Error(_) ->
      Error("Failed to start HTTP server on port " <> port_to_string(port))
  }
}

fn handle_request(
  req: Request(Connection),
  orch: Subject(OrchestratorMsg),
) -> Response(ResponseData) {
  case request.path_segments(req) {
    ["api", "health"] -> health_response()
    ["api", "perceptions"] -> perceptions_response(orch)
    ["api", "sensors"] -> sensors_response()
    _ -> not_found_response()
  }
}

fn health_response() -> Response(ResponseData) {
  json_response(
    200,
    json.object([
      #("status", json.string("ok")),
      #("version", json.string("0.1.0")),
      #("name", json.string("aether")),
    ]),
  )
}

fn perceptions_response(
  orch: Subject(OrchestratorMsg),
) -> Response(ResponseData) {
  let perceptions = orchestrator.get_perceptions(orch)
  json_response(
    200,
    json.object([
      #("perceptions", json.array(perceptions, codec.encode_perception)),
      #("count", json.int(list.length(perceptions))),
    ]),
  )
}

fn sensors_response() -> Response(ResponseData) {
  json_response(
    200,
    json.object([#("sensors", json.array([], fn(_) { json.null() }))]),
  )
}

fn not_found_response() -> Response(ResponseData) {
  json_response(404, json.object([#("error", json.string("not found"))]))
}

fn json_response(status: Int, body: json.Json) -> Response(ResponseData) {
  let bytes =
    body
    |> json.to_string()
    |> bytes_tree.from_string()

  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_header("access-control-allow-origin", "*")
  |> response.set_body(mist.Bytes(bytes))
}

@external(erlang, "erlang", "integer_to_binary")
fn port_to_string(port: Int) -> String
