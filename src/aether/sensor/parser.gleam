import aether/core/error.{type AetherError, ParseError}
import aether/signal.{type SignalKind}

const csi_magic = 0xAE01

pub type CsiFrame {
  CsiFrame(sequence: Int, data: BitArray)
}

pub fn parse_csi_frame(
  raw: BitArray,
  _kind: SignalKind,
) -> Result(CsiFrame, AetherError) {
  case raw {
    <<magic:size(16), seq:size(16), data:bytes>> if magic == csi_magic ->
      Ok(CsiFrame(sequence: seq, data: data))
    <<_magic:size(16), _:bits>> ->
      Error(ParseError("csi", "invalid magic: expected 0xAE01"))
    _ -> Error(ParseError("csi", "frame too short"))
  }
}
