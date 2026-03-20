import aether/core/error.{type AetherError, NoSensorsAvailable}
import aether/signal.{type Signal}
import gleam/int
import gleam/list

fn at(lst: List(a), index: Int) -> Result(a, Nil) {
  case lst, index {
    [head, ..], 0 -> Ok(head)
    [_, ..rest], n if n > 0 -> at(rest, n - 1)
    _, _ -> Error(Nil)
  }
}

/// Align signals within a tolerance window.
/// Uses the median timestamp as reference, rejects outliers.
pub fn align_signals(
  signals: List(Signal),
  tolerance_us tolerance: Int,
) -> Result(List(Signal), AetherError) {
  case signals {
    [] -> Error(NoSensorsAvailable)
    [single] -> Ok([single])
    _ -> {
      let timestamps = list.map(signals, fn(s) { s.timestamp })
      let sorted = list.sort(timestamps, int.compare)
      let mid = list.length(sorted) / 2
      let assert Ok(median) = at(sorted, mid)

      let aligned =
        list.filter(signals, fn(s) {
          let drift = int.absolute_value(s.timestamp - median)
          drift <= tolerance
        })

      case aligned {
        [] -> Error(NoSensorsAvailable)
        _ -> Ok(aligned)
      }
    }
  }
}
