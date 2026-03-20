-module(aether_demo_ffi).
-export([float_str/1]).

float_str(F) ->
    float_to_binary(F, [{decimals, 1}, compact]).
