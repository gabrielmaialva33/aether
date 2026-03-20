import aether/condition/ring_buffer
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn new_buffer_is_empty_test() {
  let buf = ring_buffer.new(5)
  ring_buffer.is_empty(buf) |> should.be_true()
  ring_buffer.size(buf) |> should.equal(0)
}

pub fn push_increases_size_test() {
  let buf =
    ring_buffer.new(5)
    |> ring_buffer.push(1)
    |> ring_buffer.push(2)
    |> ring_buffer.push(3)
  ring_buffer.size(buf) |> should.equal(3)
  ring_buffer.is_full(buf) |> should.be_false()
}

pub fn push_beyond_capacity_drops_oldest_test() {
  let buf =
    ring_buffer.new(3)
    |> ring_buffer.push(1)
    |> ring_buffer.push(2)
    |> ring_buffer.push(3)
    |> ring_buffer.push(4)

  ring_buffer.size(buf) |> should.equal(3)
  ring_buffer.is_full(buf) |> should.be_true()

  // Should contain [4, 3, 2] (newest first)
  let items = ring_buffer.to_list(buf)
  items |> should.equal([4, 3, 2])
}

pub fn to_list_newest_first_test() {
  let buf =
    ring_buffer.new(10)
    |> ring_buffer.push("a")
    |> ring_buffer.push("b")
    |> ring_buffer.push("c")
  ring_buffer.to_list(buf) |> should.equal(["c", "b", "a"])
}
