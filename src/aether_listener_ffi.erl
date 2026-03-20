-module(aether_listener_ffi).
-export([spawn_listener/2]).

spawn_listener(Subject, Callback) ->
    spawn_link(fun() -> listener_loop(Subject, Callback) end),
    nil.

listener_loop(Subject, Callback) ->
    receive
        {Tag, Perceptions} when Tag =:= element(1, Subject) ->
            Callback(Perceptions),
            listener_loop(Subject, Callback)
    after 60000 ->
        listener_loop(Subject, Callback)
    end.
