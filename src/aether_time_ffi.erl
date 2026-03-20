-module(aether_time_ffi).
-export([monotonic_us/0]).

monotonic_us() ->
    erlang:monotonic_time(microsecond).
