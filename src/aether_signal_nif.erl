-module(aether_signal_nif).
-export([
    tsfr_calibrate/4,
    hampel_filter/3,
    butterworth_bandpass/5,
    savgol_filter/3,
    avecsi_stabilize/2,
    spotfi_aoa/6,
    is_loaded/0
]).
-on_load(init/0).

init() ->
    PrivDir = case code:priv_dir(aether) of
        {error, bad_name} ->
            case file:get_cwd() of
                {ok, Cwd} -> filename:join(Cwd, "priv");
                _ -> "priv"
            end;
        Dir -> Dir
    end,
    NifPath = filename:join(PrivDir, "aether_signal"),
    case erlang:load_nif(NifPath, 0) of
        ok ->
            persistent_term:put(aether_signal_nif_loaded, true), ok;
        {error, {load_failed, _}} ->
            persistent_term:put(aether_signal_nif_loaded, false), ok;
        {error, {reload, _}} -> ok;
        {error, Reason} -> {error, Reason}
    end.

is_loaded() ->
    try persistent_term:get(aether_signal_nif_loaded)
    catch error:badarg -> false
    end.

tsfr_calibrate(_Amplitude, _Phase, _Subcarriers, _Antennas) ->
    erlang:nif_error(nif_not_loaded).

hampel_filter(_Data, _Window, _Threshold) ->
    erlang:nif_error(nif_not_loaded).

butterworth_bandpass(_Data, _Order, _LowHz, _HighHz, _SampleRate) ->
    erlang:nif_error(nif_not_loaded).

savgol_filter(_Data, _Window, _PolyOrder) ->
    erlang:nif_error(nif_not_loaded).

avecsi_stabilize(_Frames, _Window) ->
    erlang:nif_error(nif_not_loaded).

spotfi_aoa(_Amplitude, _Phase, _Antennas, _Subcarriers, _FreqHz, _SpacingM) ->
    erlang:nif_error(nif_not_loaded).
