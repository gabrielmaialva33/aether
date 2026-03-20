-module(aether_bridge_ffi).
-export([spawn_bridge/2]).

%% Bridge: receives Signal messages from a sensor actor Subject
%% and forwards them as IngestSignal messages to the orchestrator Subject.
%%
%% Gleam Subject = {Tag, Pid}
%% Signal arrives as {SensorTag, Signal}
%% We send {OrchestratorTag, {ingest_signal, Signal}} to orchestrator
spawn_bridge(SensorSubject, OrchSubject) ->
    SensorTag = element(1, SensorSubject),
    OrchPid = element(2, OrchSubject),
    OrchTag = element(1, OrchSubject),
    spawn_link(fun() -> bridge_loop(SensorTag, OrchPid, OrchTag) end),
    nil.

bridge_loop(SensorTag, OrchPid, OrchTag) ->
    receive
        {SensorTag, Signal} ->
            %% Forward as IngestSignal to orchestrator
            erlang:send(OrchPid, {OrchTag, {ingest_signal, Signal}}),
            bridge_loop(SensorTag, OrchPid, OrchTag)
    after 60000 ->
        bridge_loop(SensorTag, OrchPid, OrchTag)
    end.
