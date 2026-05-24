-module(graffeo_simple_graph_tests).
-moduledoc false.

-include_lib("eunit/include/eunit.hrl").

%% F-21: Parallel edge parity via add_edge path.
%% Add a→b twice with different weights. Both backends must agree on
%% no_edges, out_neighbours, in_neighbours, in_degree, out_degree, edge_meta.
parallel_edge_add_parity_test() ->
    MapG0 = graffeo:new(),
    MapG1 = graffeo:add_edge(MapG0, a, b, #{weight => 1}),
    MapG2 = graffeo:add_edge(MapG1, a, b, #{weight => 99}),

    DigG = graffeo_ets:new(),
    ok = graffeo_ets:add_edge(DigG, a, b, #{weight => 1}),
    ok = graffeo_ets:add_edge(DigG, a, b, #{weight => 99}),

    ?assertEqual(graffeo:no_edges(MapG2), graffeo:no_edges(DigG)),
    ?assertEqual(
        lists:sort(graffeo:out_neighbours(MapG2, a)),
        lists:sort(graffeo:out_neighbours(DigG, a))
    ),
    ?assertEqual(
        lists:sort(graffeo:in_neighbours(MapG2, b)),
        lists:sort(graffeo:in_neighbours(DigG, b))
    ),
    ?assertEqual(graffeo:in_degree(MapG2, b), graffeo:in_degree(DigG, b)),
    ?assertEqual(graffeo:out_degree(MapG2, a), graffeo:out_degree(DigG, a)),
    ?assertEqual(graffeo:edge_meta(MapG2, a, b), graffeo:edge_meta(DigG, a, b)),
    graffeo_ets:delete(DigG).

%% F-21: Parallel edge parity via wrap/1 of a hand-built multigraph.
parallel_edge_wrap_parity_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, x),
    digraph:add_vertex(D, y),
    digraph:add_edge(D, x, y, #{weight => 10}),
    digraph:add_edge(D, x, y, #{weight => 20}),
    digraph:add_edge(D, x, y, #{weight => 30}),
    DigG = graffeo_ets:wrap(D),

    MapG0 = graffeo:new(),
    MapG1 = graffeo:add_edge(MapG0, x, y, #{weight => 10}),
    MapG2 = graffeo:add_edge(MapG1, x, y, #{weight => 20}),
    MapG3 = graffeo:add_edge(MapG2, x, y, #{weight => 30}),

    ?assertEqual(graffeo:no_edges(MapG3), graffeo:no_edges(DigG)),
    ?assertEqual(
        lists:sort(graffeo:out_neighbours(MapG3, x)),
        lists:sort(graffeo:out_neighbours(DigG, x))
    ),
    ?assertEqual(
        lists:sort(graffeo:in_neighbours(MapG3, y)),
        lists:sort(graffeo:in_neighbours(DigG, y))
    ),
    ?assertEqual(graffeo:in_degree(MapG3, y), graffeo:in_degree(DigG, y)),
    ?assertEqual(graffeo:out_degree(MapG3, x), graffeo:out_degree(DigG, x)),
    %% F-34: edge_meta parity — last-writer (weight 30) on both backends
    ?assertEqual({ok, #{weight => 30}}, graffeo:edge_meta(MapG3, x, y)),
    ?assertEqual({ok, #{weight => 30}}, graffeo:edge_meta(DigG, x, y)),
    digraph:delete(D).

%% F-34: edge_meta is deterministic on a wrapped multigraph
edge_meta_deterministic_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_edge(D, a, b, #{weight => 1}),
    digraph:add_edge(D, a, b, #{weight => 2}),
    digraph:add_edge(D, a, b, #{weight => 3}),
    G = graffeo_ets:wrap(D),
    R1 = graffeo:edge_meta(G, a, b),
    R2 = graffeo:edge_meta(G, a, b),
    ?assertEqual(R1, R2),
    ?assertEqual({ok, #{weight => 3}}, R1),
    digraph:delete(D).
