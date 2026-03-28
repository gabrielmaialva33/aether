-module(aether_time_ffi).
-export([monotonic_us/0, now_ms/0, spawn_offline_checker/1]).

monotonic_us() ->
    erlang:monotonic_time(microsecond).

now_ms() ->
    erlang:system_time(millisecond).

spawn_offline_checker(Orch) ->
    spawn_link(fun() -> offline_loop(Orch) end),
    nil.

offline_loop(Orch) ->
    timer:sleep(2000),
    'gleam@erlang@process':send(Orch, check_offline_nodes),
    offline_loop(Orch).
