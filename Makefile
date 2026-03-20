.PHONY: build test fmt check clean nif-signal nif-brain nif

build: nif-signal
	gleam build

test:
	gleam test

fmt:
	gleam format src test

check:
	gleam check

clean:
	gleam clean

nif-signal:
	cd native/aether_signal && cargo build --release
	mkdir -p build/dev/erlang/aether/priv
	cp native/aether_signal/target/release/libaether_signal.so \
		build/dev/erlang/aether/priv/aether_signal.so

nif-brain:
	cd native/aether_brain && cargo build --release
	mkdir -p build/dev/erlang/aether/priv
	cp native/aether_brain/target/release/libaether_brain.so \
		build/dev/erlang/aether/priv/aether_brain.so

nif: nif-signal nif-brain
