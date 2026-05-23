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
    G = graffeo_digraph:new(),
    E = graffeo_digraph:empty_like(G),
    ?assertEqual(0, graffeo:no_vertices(E)),
    E2 = graffeo_digraph:build_add_vertex(E, x),
    ?assertEqual([x], graffeo:vertices(E2)),
    E3 = graffeo_digraph:build_add_vertex(E2, y, my_label),
    ?assertEqual({ok, my_label}, graffeo:vertex_label(E3, y)),
    E4 = graffeo_digraph:build_add_edge(E3, x, y, #{weight => 5}),
    ?assertEqual(1, graffeo:no_edges(E4)),
    graffeo_digraph:delete(E4),
    graffeo_digraph:delete(G).

builder_behaviour_declared_test() ->
    {ok, DigSrc} = file:read_file("src/graffeo_digraph.erl"),
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
    G = graffeo_digraph:new(),
    ok = graffeo_digraph:add_edge(G, a, b, #{weight => 1}),
    ok = graffeo_digraph:add_edge(G, b, c, #{weight => 2}),
    ok = graffeo_digraph:add_edge(G, c, d, #{weight => 3}),
    Sub = graffeo:subgraph(G, [a, b, c]),
    ?assertEqual(lists:sort([a, b, c]), lists:sort(graffeo:vertices(Sub))),
    ?assertEqual(2, graffeo:no_edges(Sub)),
    graffeo_digraph:delete(Sub),
    graffeo_digraph:delete(G).

subgraph_stdlib_parity_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_vertex(D, c),
    digraph:add_vertex(D, d),
    digraph:add_edge(D, a, b),
    digraph:add_edge(D, b, c),
    digraph:add_edge(D, c, d),
    G = graffeo_digraph:wrap(D),
    Sub = graffeo:subgraph(G, [a, b, c]),
    StdSub = digraph_utils:subgraph(D, [a, b, c]),
    ?assertEqual(
        lists:sort(digraph:vertices(StdSub)),
        lists:sort(graffeo:vertices(Sub))
    ),
    ?assertEqual(digraph:no_edges(StdSub), graffeo:no_edges(Sub)),
    digraph:delete(StdSub),
    graffeo_digraph:delete(Sub),
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
    G = graffeo_digraph:new(),
    ok = graffeo_digraph:add_edge(G, a, b),
    ok = graffeo_digraph:add_edge(G, b, c),
    ok = graffeo_digraph:add_edge(G, c, a),
    ok = graffeo_digraph:add_edge(G, c, d),
    Cond = graffeo:condensation(G),
    ?assertEqual(2, graffeo:no_vertices(Cond)),
    ?assertEqual(1, graffeo:no_edges(Cond)),
    graffeo_digraph:delete(Cond),
    graffeo_digraph:delete(G).

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
    G = graffeo_digraph:wrap(D),
    StdCond = digraph_utils:condensation(D),
    GrCond = graffeo:condensation(G),
    ?assertEqual(digraph:no_vertices(StdCond), graffeo:no_vertices(GrCond)),
    ?assertEqual(digraph:no_edges(StdCond), graffeo:no_edges(GrCond)),
    digraph:delete(StdCond),
    graffeo_digraph:delete(GrCond),
    digraph:delete(D).
