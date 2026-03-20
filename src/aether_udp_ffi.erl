-module(aether_udp_ffi).
-export([open/1, recv/2, close/1, send_to/4, spawn_receiver/2]).

%% Open a UDP socket in binary mode, active false (we poll manually).
open(Port) ->
    case gen_udp:open(Port, [binary, {active, false}, {reuseaddr, true}]) of
        {ok, Socket} -> {ok, Socket};
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end.

%% Receive a single UDP packet (blocking with timeout).
recv(Socket, TimeoutMs) ->
    case gen_udp:recv(Socket, 0, TimeoutMs) of
        {ok, {_Addr, _Port, Data}} -> {ok, Data};
        {error, timeout} -> {error, <<"timeout">>};
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end.

%% Close the UDP socket.
close(Socket) ->
    gen_udp:close(Socket),
    nil.

%% Send data to a specific address (for testing).
send_to(Host, Port, Data, _Opts) ->
    {ok, Socket} = gen_udp:open(0, [binary]),
    gen_udp:send(Socket, Host, Port, Data),
    gen_udp:close(Socket),
    nil.

%% Spawn a linked process that receives UDP packets and forwards to sensor actor.
spawn_receiver(Socket, SensorSubject) ->
    spawn_link(fun() -> receive_loop(Socket, SensorSubject) end),
    nil.

receive_loop(Socket, SensorSubject) ->
    case gen_udp:recv(Socket, 0, 5000) of
        {ok, {_Addr, _Port, Data}} ->
            %% Send RawFrame message to the sensor actor
            %% gleam_otp Subject is a pid-based subject, we send the tagged tuple
            erlang:send(element(2, SensorSubject), {element(1, SensorSubject), {raw_frame, Data}}),
            receive_loop(Socket, SensorSubject);
        {error, timeout} ->
            receive_loop(Socket, SensorSubject);
        {error, _Reason} ->
            ok
    end.
