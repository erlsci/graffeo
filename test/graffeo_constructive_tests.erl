-module(graffeo_constructive_tests).
-moduledoc false.

-include_lib("eunit/include/eunit.hrl").

%%% === M2-21: builder behaviour ===

builder_empty_like_map_test() ->
    G = graffeo:new(),
    G1 = graffeo:add_edge(G, a, b),
    E = graffeo_map:empty_like(G1),
    ?assertEqual(0, graffeo:no_vertices(E)),
    ?assertEqual(0, graffeo:no_edges(E)),
    E2 = graffeo_map:build_add_vertex(E, x),
    ?assertEqual([x], graffeo:vertices(E2)),
    E3 = graffeo_map:build_add_vertex(E2, y, my_label),
    ?assertEqual({ok, my_label}, graffeo:vertex_label(E3, y)),
    E4 = graffeo_map:build_add_edge(E3, x, y, #{weight => 5}),
    ?assertEqual(1, graffeo:no_edges(E4)).

builder_empty_like_digraph_test() ->
    G = graffeo_ets:new(),
    E = graffeo_ets:empty_like(G),
    ?assertEqual(0, graffeo:no_vertices(E)),
    E2 = graffeo_ets:build_add_vertex(E, x),
    ?assertEqual([x], graffeo:vertices(E2)),
    E3 = graffeo_ets:build_add_vertex(E2, y, my_label),
    ?assertEqual({ok, my_label}, graffeo:vertex_label(E3, y)),
    E4 = graffeo_ets:build_add_edge(E3, x, y, #{weight => 5}),
    ?assertEqual(1, graffeo:no_edges(E4)),
    graffeo_ets:delete(E4),
    graffeo_ets:delete(G).

builder_behaviour_declared_test() ->
    {ok, DigSrc} = file:read_file("src/graffeo_ets.erl"),
    ?assertNotEqual(nomatch, binary:match(DigSrc, <<"behaviour(graffeo_builder)">>)),
    {ok, MapSrc} = file:read_file("src/graffeo_map.erl"),
    ?assertNotEqual(nomatch, binary:match(MapSrc, <<"behaviour(graffeo_builder)">>)).

%%% === M2-22: subgraph ===

subgraph_map_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b, #{weight => 1}),
    G2 = graffeo:add_edge(G1, b, c, #{weight => 2}),
    G3 = graffeo:add_edge(G2, c, d, #{weight => 3}),
    Sub = graffeo:subgraph(G3, [a, b, c]),
    ?assertEqual(lists:sort([a, b, c]), lists:sort(graffeo:vertices(Sub))),
    ?assertEqual(2, graffeo:no_edges(Sub)),
    ?assertEqual({ok, #{weight => 1}}, graffeo:edge_meta(Sub, a, b)),
    ?assertEqual({ok, #{weight => 2}}, graffeo:edge_meta(Sub, b, c)),
    ?assertEqual(error, graffeo:edge_meta(Sub, c, d)).

subgraph_digraph_test() ->
    G = graffeo_ets:new(),
    ok = graffeo_ets:add_edge(G, a, b, #{weight => 1}),
    ok = graffeo_ets:add_edge(G, b, c, #{weight => 2}),
    ok = graffeo_ets:add_edge(G, c, d, #{weight => 3}),
    OrigVerts = lists:sort(graffeo:vertices(G)),
    Sub = graffeo:subgraph(G, [a, b, c]),
    ?assertEqual(lists:sort([a, b, c]), lists:sort(graffeo:vertices(Sub))),
    ?assertEqual(2, graffeo:no_edges(Sub)),
    %% MUST-6: prove non-aliasing — deleting result leaves source intact
    graffeo_ets:delete(Sub),
    ?assertEqual(OrigVerts, lists:sort(graffeo:vertices(G))),
    graffeo_ets:delete(G).

%% MUST-3: stdlib parity compares edge set, not just count
subgraph_stdlib_parity_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_vertex(D, c),
    digraph:add_vertex(D, d),
    digraph:add_edge(D, a, b, my_meta),
    digraph:add_edge(D, b, c, other_meta),
    digraph:add_edge(D, c, d),
    G = graffeo_ets:wrap(D),
    Sub = graffeo:subgraph(G, [a, b, c]),
    StdSub = digraph_utils:subgraph(D, [a, b, c]),
    ?assertEqual(
        lists:sort(digraph:vertices(StdSub)),
        lists:sort(graffeo:vertices(Sub))
    ),
    StdEdges = edge_pairs(StdSub),
    GrEdges = graffeo_edge_pairs(Sub),
    ?assertEqual(lists:sort(StdEdges), lists:sort(GrEdges)),
    digraph:delete(StdSub),
    graffeo_ets:delete(Sub),
    digraph:delete(D).

%% MUST-1: subgraph/3 with options
subgraph_opts_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_vertex(G0, a, my_label),
    G2 = graffeo:add_edge(G1, a, b, #{weight => 5}),
    %% keep_labels = true (default)
    Sub1 = graffeo:subgraph(G2, [a, b]),
    ?assertEqual({ok, my_label}, graffeo:vertex_label(Sub1, a)),
    ?assertEqual({ok, #{weight => 5}}, graffeo:edge_meta(Sub1, a, b)),
    %% keep_labels = false
    Sub2 = graffeo:subgraph(G2, [a, b], [{keep_labels, false}]),
    ?assertNotEqual({ok, my_label}, graffeo:vertex_label(Sub2, a)),
    ?assertEqual({ok, #{}}, graffeo:edge_meta(Sub2, a, b)),
    %% badarg on malformed options
    ?assertError(badarg, graffeo:subgraph(G2, [a, b], [invalid])).

subgraph_opts_stdlib_parity_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a, my_label),
    digraph:add_vertex(D, b),
    digraph:add_edge(D, a, b, my_meta),
    G = graffeo_ets:wrap(D),
    StdSub = digraph_utils:subgraph(D, [a, b], [{keep_labels, false}]),
    GrSub = graffeo:subgraph(G, [a, b], [{keep_labels, false}]),
    ?assertEqual(
        lists:sort(digraph:vertices(StdSub)),
        lists:sort(graffeo:vertices(GrSub))
    ),
    ?assertEqual(lists:sort(edge_pairs(StdSub)), lists:sort(graffeo_edge_pairs(GrSub))),
    digraph:delete(StdSub),
    graffeo_ets:delete(GrSub),
    digraph:delete(D).

subgraph_preserves_labels_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_vertex(G0, a, my_label),
    G2 = graffeo:add_edge(G1, a, b),
    Sub = graffeo:subgraph(G2, [a, b]),
    ?assertEqual({ok, my_label}, graffeo:vertex_label(Sub, a)).

%%% === M2-23: condensation ===

condensation_map_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    G3 = graffeo:add_edge(G2, c, a),
    G4 = graffeo:add_edge(G3, c, d),
    Cond = graffeo:condensation(G4),
    Verts = graffeo:vertices(Cond),
    ?assertEqual(2, length(Verts)),
    SCCVerts = lists:sort(lists:flatmap(fun(V) -> V end, Verts)),
    ?assertEqual([a, b, c, d], SCCVerts),
    ?assertEqual(1, graffeo:no_edges(Cond)).

condensation_digraph_test() ->
    G = graffeo_ets:new(),
    ok = graffeo_ets:add_edge(G, a, b),
    ok = graffeo_ets:add_edge(G, b, c),
    ok = graffeo_ets:add_edge(G, c, a),
    ok = graffeo_ets:add_edge(G, c, d),
    OrigVerts = lists:sort(graffeo:vertices(G)),
    Cond = graffeo:condensation(G),
    ?assertEqual(2, graffeo:no_vertices(Cond)),
    ?assertEqual(1, graffeo:no_edges(Cond)),
    %% MUST-6: prove non-aliasing
    graffeo_ets:delete(Cond),
    ?assertEqual(OrigVerts, lists:sort(graffeo:vertices(G))),
    graffeo_ets:delete(G).

%% MUST-2: compare member-list vertices + edge set, not just counts
condensation_stdlib_parity_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_vertex(D, c),
    digraph:add_vertex(D, d),
    digraph:add_edge(D, a, b),
    digraph:add_edge(D, b, c),
    digraph:add_edge(D, c, a),
    digraph:add_edge(D, c, d),
    G = graffeo_ets:wrap(D),
    StdCond = digraph_utils:condensation(D),
    GrCond = graffeo:condensation(G),
    StdVerts = lists:sort([lists:sort(V) || V <- digraph:vertices(StdCond)]),
    GrVerts = lists:sort([lists:sort(V) || V <- graffeo:vertices(GrCond)]),
    ?assertEqual(StdVerts, GrVerts),
    StdCondEdges = lists:sort([
        {lists:sort(F), lists:sort(T)}
     || E <- digraph:edges(StdCond),
        {_, F, T, _} <- [digraph:edge(StdCond, E)]
    ]),
    GrCondEdges = lists:sort(
        lists:flatmap(
            fun(V) ->
                [{lists:sort(V), lists:sort(N)} || N <- graffeo:out_neighbours(GrCond, V)]
            end,
            graffeo:vertices(GrCond)
        )
    ),
    ?assertEqual(StdCondEdges, GrCondEdges),
    digraph:delete(StdCond),
    graffeo_ets:delete(GrCond),
    digraph:delete(D).

%%% --- helpers ---

edge_pairs(D) ->
    [
        {F, T}
     || E <- digraph:edges(D),
        {_, F, T, _} <- [digraph:edge(D, E)]
    ].

graffeo_edge_pairs(G) ->
    lists:flatmap(
        fun(V) -> [{V, N} || N <- graffeo:out_neighbours(G, V)] end,
        graffeo:vertices(G)
    ).
