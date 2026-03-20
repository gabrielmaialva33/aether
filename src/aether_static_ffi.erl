-module(aether_static_ffi).
-export([priv_dir/0]).

priv_dir() ->
    case code:priv_dir(aether) of
        {error, bad_name} ->
            case file:get_cwd() of
                {ok, Cwd} -> unicode:characters_to_binary(filename:join(Cwd, "priv/static"));
                _ -> <<"priv/static">>
            end;
        Dir -> unicode:characters_to_binary(filename:join(Dir, "static"))
    end.
