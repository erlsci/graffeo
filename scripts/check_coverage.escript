#!/usr/bin/env escript
%% -*- erlang -*-
%%! -pa _build/test/lib/graffeo/ebin

-define(THRESHOLD, 95).
-define(COVERDATA_FILES, [
    "_build/test/cover/eunit.coverdata",
    "_build/test/cover/ct.coverdata",
    "_build/test/cover/proper.coverdata"
]).
-define(MODULES, [
    graffeo,
    graffeo_backend,
    graffeo_builder,
    graffeo_conn,
    graffeo_digraph,
    graffeo_map,
    graffeo_path,
    graffeo_traverse
]).

main(_Args) ->
    lists:foreach(
        fun(F) ->
            case filelib:is_file(F) of
                true -> cover:import(F);
                false -> ok
            end
        end,
        ?COVERDATA_FILES
    ),
    {TotalCov, TotalUncov} = lists:foldl(
        fun(Mod, {CovAcc, UncovAcc}) ->
            case cover:analyse(Mod, calls, line) of
                {ok, Lines} ->
                    Cov = length([1 || {{_, _}, N} <- Lines, N > 0]),
                    Uncov = length([1 || {{_, _}, N} <- Lines, N =:= 0]),
                    Pct = case Cov + Uncov of
                        0 -> 100;
                        T -> Cov * 100 div T
                    end,
                    io:format("  ~-25s ~3w%  (~w/~w)~n", [Mod, Pct, Cov, Cov + Uncov]),
                    {CovAcc + Cov, UncovAcc + Uncov};
                {error, _} ->
                    io:format("  ~-25s  (no data)~n", [Mod]),
                    {CovAcc, UncovAcc}
            end
        end,
        {0, 0},
        ?MODULES
    ),
    Total = TotalCov + TotalUncov,
    Pct = case Total of
        0 -> 100;
        _ -> TotalCov * 100 div Total
    end,
    io:format("~n  Total: ~w% (~w/~w executable lines)~n", [Pct, TotalCov, Total]),
    io:format("  Threshold: ~w%~n", [?THRESHOLD]),
    case Pct >= ?THRESHOLD of
        true ->
            io:format("  PASS~n"),
            halt(0);
        false ->
            io:format("  FAIL: coverage ~w% < ~w%~n", [Pct, ?THRESHOLD]),
            halt(1)
    end.
