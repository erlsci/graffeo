-module(erlc_ingest_tests).
-include_lib("eunit/include/eunit.hrl").

-define(CARDS_DIR,
    "../../workbench/ai-engineering/knowledge/erlang/concept-cards"
).

cards_available() ->
    filelib:is_dir(?CARDS_DIR).

source_vertex_count_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                Result = erlc_ingest:build_from_dir(?CARDS_DIR),
                G = maps:get(graph, Result),
                SrcVs = erlc_ingest:source_vertices(G),
                ?assertEqual(1664, length(SrcVs))
        end
    end}.

abstract_vertex_count_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                Result = erlc_ingest:build_from_dir(?CARDS_DIR),
                G = maps:get(graph, Result),
                AbsVs = erlc_ingest:abstract_vertices(G),
                ?assertEqual(1397, length(AbsVs))
        end
    end}.

membership_edge_count_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                Result = erlc_ingest:build_from_dir(?CARDS_DIR),
                G = maps:get(graph, Result),
                SrcVs = erlc_ingest:source_vertices(G),
                MemberCount = lists:foldl(
                    fun(From, Acc) ->
                        OutNbrs = graffeo:out_neighbours(G, From),
                        Acc + length([N || N <- OutNbrs, is_binary(N)])
                    end,
                    0,
                    SrcVs
                ),
                ?assertEqual(1664, MemberCount)
        end
    end}.

reverse_traversal_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                Result = erlc_ingest:build_from_dir(?CARDS_DIR),
                G = maps:get(graph, Result),
                InNbrs = graffeo:in_neighbours(G, <<"gen-server">>),
                Siblings = [V || V <- InNbrs, is_tuple(V)],
                ?assert(length(Siblings) >= 3)
        end
    end}.

determinism_test_() ->
    {timeout, 600, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                R1 = erlc_ingest:build_from_dir(?CARDS_DIR),
                R2 = erlc_ingest:build_from_dir(?CARDS_DIR),
                G1 = maps:get(graph, R1),
                G2 = maps:get(graph, R2),
                V1 = lists:sort(graffeo:vertices(G1)),
                V2 = lists:sort(graffeo:vertices(G2)),
                ?assertEqual(V1, V2),
                ?assertEqual(graffeo:no_edges(G1), graffeo:no_edges(G2))
        end
    end}.

ghost_concepts_test_() ->
    {timeout, 300, fun() ->
        case cards_available() of
            false ->
                ok;
            true ->
                Result = erlc_ingest:build_from_dir(?CARDS_DIR),
                G = maps:get(graph, Result),
                AbsVs = erlc_ingest:abstract_vertices(G),
                Ghosts = lists:sort(
                    lists:filter(
                        fun(Slug) ->
                            InNbrs = graffeo:in_neighbours(G, Slug),
                            not lists:any(fun is_tuple/1, InNbrs)
                        end,
                        AbsVs
                    )
                ),
                ?assert(lists:member(<<"erlang-ports">>, Ghosts)),
                ?assert(lists:member(<<"os-system-time">>, Ghosts))
        end
    end}.

small_graph_test() ->
    Cards = [
        #{
            slug => <<"a">>,
            concept => <<"A">>,
            category => <<"cat">>,
            tier => <<"basic">>,
            source => <<"Book">>,
            source_slug => <<"book">>,
            prerequisites => [<<"b">>],
            extends => [],
            related => [<<"c">>],
            contrasts_with => []
        },
        #{
            slug => <<"b">>,
            concept => <<"B">>,
            category => <<"cat">>,
            tier => <<"basic">>,
            source => <<"Book">>,
            source_slug => <<"book">>,
            prerequisites => [],
            extends => [],
            related => [],
            contrasts_with => []
        },
        #{
            slug => <<"c">>,
            concept => <<"C">>,
            category => <<"cat">>,
            tier => <<"basic">>,
            source => <<"Book">>,
            source_slug => <<"book">>,
            prerequisites => [],
            extends => [],
            related => [<<"a">>],
            contrasts_with => []
        }
    ],
    Result = erlc_ingest:build(Cards),
    G = maps:get(graph, Result),
    ?assertEqual(3, maps:get(source_count, Result)),
    ?assertEqual(3, maps:get(abstract_count, Result)),
    ?assertEqual(6, graffeo:no_vertices(G)),
    SrcVs = erlc_ingest:source_vertices(G),
    ?assertEqual(3, length(SrcVs)),
    AbsVs = erlc_ingest:abstract_vertices(G),
    ?assertEqual(3, length(AbsVs)),
    ?assertEqual(
        3,
        length([
            V
         || V <- graffeo:out_neighbours(G, {<<"book">>, <<"a">>}),
            is_binary(V) orelse is_tuple(V)
        ])
    ).
