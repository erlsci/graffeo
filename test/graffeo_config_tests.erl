-module(graffeo_config_tests).
-moduledoc false.

-include_lib("eunit/include/eunit.hrl").

data_dir_returns_string_test() ->
    Dir = graffeo_config:data_dir(),
    ?assert(is_list(Dir)),
    ?assert(filelib:is_dir(Dir)).

data_dir_default_is_stable_test() ->
    Dir1 = graffeo_config:data_dir(),
    Dir2 = graffeo_config:data_dir(),
    ?assertEqual(Dir1, Dir2).

data_dir_explicit_string_override_test() ->
    TmpDir = filename:join(filename:basedir(user_cache, "graffeo"), "test_str"),
    ok = application:set_env(graffeo, data_dir, TmpDir),
    ?assertEqual(TmpDir, graffeo_config:data_dir()),
    ?assert(filelib:is_dir(TmpDir)),
    application:set_env(graffeo, data_dir, default),
    file:del_dir(TmpDir).

data_dir_explicit_binary_override_test() ->
    TmpDir = filename:join(filename:basedir(user_cache, "graffeo"), "test_bin"),
    ok = application:set_env(graffeo, data_dir, list_to_binary(TmpDir)),
    ?assertEqual(TmpDir, graffeo_config:data_dir()),
    application:set_env(graffeo, data_dir, default),
    file:del_dir(TmpDir).

data_dir_default_resolves_test() ->
    ok = application:set_env(graffeo, data_dir, default),
    Dir = graffeo_config:data_dir(),
    ?assert(is_list(Dir)),
    ?assert(filelib:is_dir(Dir)).

%%% === resolve_candidates/1 ===

resolve_candidates_first_writable_test() ->
    Dir = filename:join(filename:basedir(user_cache, "graffeo"), "cand_test"),
    {ok, Dir} = graffeo_config:resolve_candidates([Dir]),
    ?assert(filelib:is_dir(Dir)),
    file:del_dir(Dir).

resolve_candidates_skips_unwritable_test() ->
    Good = filename:join(filename:basedir(user_cache, "graffeo"), "cand_good"),
    {ok, Good} = graffeo_config:resolve_candidates(["/proc/no_such_path", Good]),
    file:del_dir(Good).

resolve_candidates_empty_list_test() ->
    ?assertEqual(error, graffeo_config:resolve_candidates([])).

resolve_candidates_all_unwritable_test() ->
    ?assertEqual(
        error,
        graffeo_config:resolve_candidates(
            ["/proc/no_such_path", "/proc/also_no"]
        )
    ).

%%% === build_candidates/1 ===

build_candidates_with_priv_dir_test() ->
    Candidates = graffeo_config:build_candidates("/some/priv"),
    ?assertMatch(["/some/priv/data", _, _], Candidates).

build_candidates_without_priv_dir_test() ->
    Candidates = graffeo_config:build_candidates({error, bad_name}),
    ?assertMatch(["graffeo_data", _], Candidates).
