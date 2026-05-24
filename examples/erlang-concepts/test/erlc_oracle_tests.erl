-module(erlc_oracle_tests).
-moduledoc """
Oracle-parity gate for the erlang-concepts example.

Asserts that every anchored fact computed by the example code matches
the committed `oracle/expected.json`. The JSON is regenerated only
when the pinned corpus tag moves, using `oracle/oracle.py`; CI never
runs Python. This module reads the committed JSON as a fixed reference.
""".

-include_lib("eunit/include/eunit.hrl").

oracle_parity_test_() ->
    {timeout, 300, fun() ->
        Expected = load_expected(),
        #{graph := G, abstract_count := AbsCount} =
            erlc_ingest:build_from_dir(erlc:cards_dir()),
        assert_source_vertices(Expected, G),
        assert_abstract_vertices(Expected, AbsCount),
        assert_edge_counts_by_type(Expected, G),
        assert_prerequisite_cycles(Expected, G),
        assert_related_components(Expected, G),
        assert_semantic_components(Expected, G),
        assert_top_k(Expected, G),
        assert_five_book_slugs(Expected, G),
        assert_ghosts(Expected, G)
    end}.

load_expected() ->
    {ok, Bin} = file:read_file("oracle/expected.json"),
    json:decode(Bin).

assert_source_vertices(E, G) ->
    Exp = maps:get(<<"n_source_vertices">>, E),
    Got = length(erlc_ingest:source_vertices(G)),
    ?assertEqual(Exp, Got, "n_source_vertices").

assert_abstract_vertices(E, AbsCount) ->
    Exp = maps:get(<<"n_abstract_vertices">>, E),
    ?assertEqual(Exp, AbsCount, "n_abstract_vertices (card-derived only)").

assert_edge_counts_by_type(E, G) ->
    ExpMap = maps:get(<<"abstract_edge_assertions_by_type">>, E),
    Types = [
        {prerequisites, <<"prerequisites">>},
        {related, <<"related">>},
        {extends, <<"extends">>},
        {contrasts_with, <<"contrasts_with">>}
    ],
    lists:foreach(
        fun({Type, Key}) ->
            Exp = maps:get(Key, ExpMap),
            Proj = graffeo:filter_edges(G, fun(From, To, Meta) ->
                is_binary(From) andalso is_binary(To) andalso
                    has_type(Meta, Type)
            end),
            Got = graffeo:no_edges(Proj),
            ?assertEqual(Exp, Got, binary_to_list(Key))
        end,
        Types
    ).

assert_prerequisite_cycles(E, G) ->
    ExpN = maps:get(<<"n_prereq_cycles">>, E),
    ExpSCCs = maps:get(<<"prereq_cyclic_strong_components">>, E),
    {true, Cycles} = erlc_queries:prerequisite_cycles(G),
    ?assertEqual(ExpN, length(Cycles), "n_prereq_cycles"),
    NormExp = normalize_sccs(ExpSCCs),
    NormGot = normalize_sccs(Cycles),
    ?assertEqual(NormExp, NormGot, "prereq_cyclic_strong_components").

assert_related_components(E, G) ->
    ExpN = maps:get(<<"related_n_components">>, E),
    ExpGiant = maps:get(<<"related_giant_size">>, E),
    {GotN, GotGiant, _} = erlc_queries:related_components(G),
    ?assertEqual(ExpN, GotN, "related_n_components"),
    ?assertEqual(ExpGiant, GotGiant, "related_giant_size").

assert_semantic_components(E, G) ->
    ExpN = maps:get(<<"all_relations_n_components">>, E),
    ExpGiant = maps:get(<<"all_relations_giant_size">>, E),
    {GotN, GotGiant, _} = erlc_queries:semantic_components(G),
    ?assertEqual(ExpN, GotN, "all_relations_n_components"),
    ?assertEqual(ExpGiant, GotGiant, "all_relations_giant_size").

assert_top_k(E, G) ->
    ExpList = maps:get(<<"top_k_by_total_degree">>, E),
    K = length(ExpList),
    GotTuples = erlc_queries:top_concepts_by_degree(G, K),
    GotList = [[S, D] || {S, D} <- GotTuples],
    ?assertEqual(ExpList, GotList, "top_k_by_total_degree").

assert_five_book_slugs(E, G) ->
    ExpSlugs = lists:sort(maps:get(<<"five_book_slugs">>, E)),
    CB = erlc_queries:coverage_breadth(G),
    GotSlugs = lists:sort([S || {S, N} <- CB, N >= 5]),
    ?assertEqual(ExpSlugs, GotSlugs, "five_book_slugs").

assert_ghosts(E, G) ->
    ExpGhosts = lists:sort(maps:get(<<"ghost_concepts">>, E)),
    GotGhosts = lists:sort(erlc_queries:ghost_concepts(G)),
    ?assertEqual(ExpGhosts, GotGhosts, "ghost_concepts").

has_type(#{label := #{types := Types}}, Type) ->
    lists:member(Type, Types);
has_type(_, _) ->
    false.

normalize_sccs(SCCs) ->
    lists:sort([lists:sort(C) || C <- SCCs]).
