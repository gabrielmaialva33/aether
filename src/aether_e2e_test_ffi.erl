-module(aether_e2e_test_ffi).
-export([udp_send_to/3]).

udp_send_to(Host, Port, Data) ->
    {ok, Socket} = gen_udp:open(0, [binary]),
    ok = gen_udp:send(Socket, Host, Port, Data),
    gen_udp:close(Socket),
    nil.
