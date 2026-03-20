-module(aether_brain_nif).
-export([
    load_model/2,
    foundation_infer/3,
    cross_modal_fuse/2,
    model_info/1,
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
    NifPath = filename:join(PrivDir, "aether_brain"),
    case erlang:load_nif(NifPath, 0) of
        ok ->
            persistent_term:put(aether_brain_nif_loaded, true), ok;
        {error, {load_failed, _}} ->
            persistent_term:put(aether_brain_nif_loaded, false), ok;
        {error, {reload, _}} -> ok;
        {error, Reason} -> {error, Reason}
    end.

is_loaded() ->
    try persistent_term:get(aether_brain_nif_loaded)
    catch error:badarg -> false
    end.

load_model(_Path, _Device) ->
    erlang:nif_error(nif_not_loaded).

foundation_infer(_Model, _Embedding, _Tasks) ->
    erlang:nif_error(nif_not_loaded).

cross_modal_fuse(_Embeddings, _ModalityIds) ->
    erlang:nif_error(nif_not_loaded).

model_info(_Model) ->
    erlang:nif_error(nif_not_loaded).
