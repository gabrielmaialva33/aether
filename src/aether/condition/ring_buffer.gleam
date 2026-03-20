/// Ring buffer for CSI frame stabilization.
/// Stores the last N frames for AveCSI sliding window averaging.
import gleam/list

pub opaque type RingBuffer(a) {
  RingBuffer(items: List(a), capacity: Int, size: Int)
}

/// Create a new ring buffer with given capacity.
pub fn new(capacity: Int) -> RingBuffer(a) {
  RingBuffer(items: [], capacity: capacity, size: 0)
}

/// Push an item into the buffer. If full, oldest item is dropped.
pub fn push(buffer: RingBuffer(a), item: a) -> RingBuffer(a) {
  case buffer.size >= buffer.capacity {
    True -> {
      // Drop oldest (last in list), add new at head
      let trimmed = list.take(buffer.items, buffer.capacity - 1)
      RingBuffer(
        items: [item, ..trimmed],
        capacity: buffer.capacity,
        size: buffer.capacity,
      )
    }
    False ->
      RingBuffer(
        items: [item, ..buffer.items],
        capacity: buffer.capacity,
        size: buffer.size + 1,
      )
  }
}

/// Get all items in the buffer (newest first).
pub fn to_list(buffer: RingBuffer(a)) -> List(a) {
  buffer.items
}

/// Get the number of items currently in the buffer.
pub fn size(buffer: RingBuffer(a)) -> Int {
  buffer.size
}

/// Check if buffer is empty.
pub fn is_empty(buffer: RingBuffer(a)) -> Bool {
  buffer.size == 0
}

/// Check if buffer is at capacity.
pub fn is_full(buffer: RingBuffer(a)) -> Bool {
  buffer.size >= buffer.capacity
}
