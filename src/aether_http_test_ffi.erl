-module(aether_http_test_ffi).
-export([http_get/1]).

http_get(Url) ->
    inets:start(),
    ssl:start(),
    case httpc:request(get, {binary_to_list(Url), []}, [{timeout, 5000}], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, Body}} -> {ok, Body};
        {ok, {{_, 404, _}, _, Body}} -> {ok, Body};
        {ok, {{_, Code, _}, _, Body}} -> {ok, Body};
        {error, Reason} -> {error, list_to_binary(io_lib:format("~p", [Reason]))}
    end.
