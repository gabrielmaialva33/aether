/// Æther HTTP + WebSocket API Server
///
/// REST:
///   GET  /api/health       → system health
///   GET  /api/perceptions  → latest perceptions
///   GET  /api/sensors      → sensor status
///
/// WebSocket:
///   ws://host:port/ws/stream  → real-time perception push
import aether/orchestrator.{type OrchestratorMsg}
import aether/perception.{type Perception}
import aether/serve/codec
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{Some}
import mist.{type Connection, type ResponseData, type WebsocketConnection}

/// Start the HTTP/WebSocket server.
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
    ["ws", "stream"] -> ws_stream(req, orch)
    _ -> not_found_response()
  }
}

// ─── REST Endpoints ─────────────────────────────────────────────────────────

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
  let bytes = body |> json.to_string() |> bytes_tree.from_string()
  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_header("access-control-allow-origin", "*")
  |> response.set_body(mist.Bytes(bytes))
}

// ─── WebSocket: /ws/stream ──────────────────────────────────────────────────

/// WebSocket state: holds the perception subscription subject.
type WsState {
  WsState
}

fn ws_stream(
  req: Request(Connection),
  orch: Subject(OrchestratorMsg),
) -> Response(ResponseData) {
  // Create a subject to receive perception updates from the orchestrator
  let perception_sub: Subject(List(Perception)) = process.new_subject()
  orchestrator.subscribe(orch, perception_sub)

  mist.websocket(
    request: req,
    handler: ws_handler,
    on_init: fn(_conn) {
      // Build a selector that receives perception updates as Custom messages
      let selector =
        process.new_selector()
        |> process.select(for: perception_sub)

      #(WsState, Some(selector))
    },
    on_close: fn(_state) { Nil },
  )
}

fn ws_handler(
  state: WsState,
  msg: mist.WebsocketMessage(List(Perception)),
  conn: WebsocketConnection,
) -> mist.Next(WsState, List(Perception)) {
  case msg {
    mist.Text("ping") -> {
      let _ = mist.send_text_frame(conn, "pong")
      mist.continue(state)
    }
    mist.Custom(perceptions) -> {
      // Encode perceptions and push to client
      let payload =
        json.object([
          #("perceptions", json.array(perceptions, codec.encode_perception)),
          #("count", json.int(list.length(perceptions))),
        ])
        |> json.to_string()
      let _ = mist.send_text_frame(conn, payload)
      mist.continue(state)
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    _ -> mist.continue(state)
  }
}

@external(erlang, "erlang", "integer_to_binary")
fn port_to_string(port: Int) -> String
