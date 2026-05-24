-module(graffeo_config).
-moduledoc """
Application-level configuration for graffeo's on-disk backends.

The primary export is `data_dir/0`, which resolves where DETS (and
future Mnesia) files are stored. Resolution chain:

1. Explicit `data_dir` from `sys.config` / `application:set_env` —
   used as-is.
2. `code:priv_dir(graffeo)/data` — if the directory is writable.
3. `graffeo_data/` under the current working directory — Mnesia-style
   writable fallback.
4. The OS user-cache directory — last resort.

**Production note:** `priv/` is often read-only in an OTP release.
Production deployments should set `data_dir` explicitly in
`sys.config`. The priv default is a dev/test/example convenience.
""".

-export([data_dir/0, resolve_candidates/1, build_candidates/1]).

-doc "Resolve the data directory for on-disk backends.".
-spec data_dir() -> file:filename_all().
data_dir() ->
    case application:get_env(graffeo, data_dir, default) of
        default ->
            Candidates = build_candidates(code:priv_dir(graffeo)),
            {ok, Dir} = resolve_candidates(Candidates),
            Dir;
        Dir when is_list(Dir) ->
            ensure(Dir);
        Dir when is_binary(Dir) ->
            ensure(binary_to_list(Dir))
    end.

-doc """
Build the ordered candidate list from a `code:priv_dir/1` result.

Exported for testability: pass `{error, bad_name}` to simulate a
missing priv directory and exercise the fallback chain.
""".
-spec build_candidates(file:filename_all() | {error, term()}) ->
    [file:filename_all()].
build_candidates({error, _}) ->
    ["graffeo_data", filename:basedir(user_cache, "graffeo")];
build_candidates(PrivDir) ->
    [
        filename:join(PrivDir, "data"),
        "graffeo_data",
        filename:basedir(user_cache, "graffeo")
    ].

-doc """
Return the first writable candidate directory.

Tries each directory in order; returns `{ok, Dir}` for the first one
where `filelib:ensure_dir/1` succeeds, or `error` if none are writable.
""".
-spec resolve_candidates([file:filename_all()]) ->
    {ok, file:filename_all()} | error.
resolve_candidates([]) ->
    error;
resolve_candidates([Dir | Rest]) ->
    case filelib:ensure_dir(filename:join(Dir, "probe")) of
        ok -> {ok, Dir};
        {error, _} -> resolve_candidates(Rest)
    end.

-spec ensure(file:filename_all()) -> file:filename_all().
ensure(Dir) ->
    ok = filelib:ensure_dir(filename:join(Dir, "probe")),
    Dir.
