-module(erlc_queries_tests).
-include_lib("eunit/include/eunit.hrl").

-define(CARDS_DIR,
    "../../workbench/ai-engineering/knowledge/erlang/concept-cards"
).

cards_available() ->
    filelib:is_dir(?CARDS_DIR).

build_graph() ->
    Result = erlc_ingest:build_from_dir(?CARDS_DIR),
    maps:get(graph, Result).

prerequisite_cycles_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                G = build_graph(),
                {IsCyclic, Cycles} = erlc_queries:prerequisite_cycles(G),
                ?assert(IsCyclic),
                ?assert(length(Cycles) >= 5),
                CycleSet = sets:from_list(
                    [sets:from_list(C, [{version, 2}]) || C <- Cycles],
                    [{version, 2}]
                ),
                ExpectedPairs = [
                    [<<"event-handler">>, <<"gen-event-behavior">>],
                    [
                        <<"application-upgrade-file">>,
                        <<"release-handling-instructions">>
                    ],
                    [<<"automatic-shutdown">>, <<"significant-child">>],
                    [<<"ct-test-case">>, <<"ct-test-suite">>],
                    [<<"port-program">>, <<"port-protocol">>]
                ],
                lists:foreach(
                    fun(Pair) ->
                        PairSet = sets:from_list(Pair, [{version, 2}]),
                        ?assert(sets:is_element(PairSet, CycleSet))
                    end,
                    ExpectedPairs
                )
        end
    end}.

learning_order_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                G = build_graph(),
                {ok, Order} = erlc_queries:learning_order(G),
                ?assertMatch([_ | _], Order)
        end
    end}.

related_components_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                G = build_graph(),
                {CompCount, GiantSize, _} =
                    erlc_queries:related_components(G),
                ?assert(CompCount > 0),
                ?assert(GiantSize > 500)
        end
    end}.

top_concepts_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                G = build_graph(),
                TopK = erlc_queries:top_concepts_by_degree(G, 5),
                ?assertEqual(5, length(TopK)),
                TopSlugs = [S || {S, _} <- TopK],
                ?assert(lists:member(<<"gen-server">>, TopSlugs)),
                ?assert(lists:member(<<"pattern-matching">>, TopSlugs))
        end
    end}.

coverage_breadth_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                G = build_graph(),
                CB = erlc_queries:coverage_breadth(G),
                FiveBook = [S || {S, N} <- CB, N >= 5],
                ?assertEqual(5, length(FiveBook)),
                Expected = [
                    <<"gen-server">>,
                    <<"pattern-matching">>,
                    <<"supervision-tree">>,
                    <<"child-specification">>,
                    <<"otp-application">>
                ],
                lists:foreach(
                    fun(S) ->
                        ?assert(lists:member(S, FiveBook))
                    end,
                    Expected
                )
        end
    end}.

ghost_concepts_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                G = build_graph(),
                Ghosts = erlc_queries:ghost_concepts(G),
                ?assert(lists:member(<<"erlang-ports">>, Ghosts)),
                ?assert(lists:member(<<"os-system-time">>, Ghosts))
        end
    end}.

tunable_relatedness_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                G = build_graph(),
                Local = erlc_queries:related_cheap(
                    G,
                    <<"programming-erlang">>,
                    <<"gen-server">>
                ),
                Extended = erlc_queries:related_extended(
                    G,
                    <<"programming-erlang">>,
                    <<"gen-server">>
                ),
                ?assertMatch([_ | _], Local),
                ?assert(length(Extended) >= length(Local)),
                IsSuperset = lists:all(
                    fun(X) -> lists:member(X, Extended) end, Local
                ),
                ?assert(IsSuperset)
        end
    end}.
