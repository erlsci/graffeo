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

    D = digraph:new(),
    ok = graffeo_digraph:add_edge(D, a, b, #{weight => 1}),
    ok = graffeo_digraph:add_edge(D, a, b, #{weight => 99}),
    DigG = graffeo_digraph:wrap(D),

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
    digraph:delete(D).

%% F-21: Parallel edge parity via wrap/1 of a hand-built multigraph.
parallel_edge_wrap_parity_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, x),
    digraph:add_vertex(D, y),
    digraph:add_edge(D, x, y, #{weight => 10}),
    digraph:add_edge(D, x, y, #{weight => 20}),
    digraph:add_edge(D, x, y, #{weight => 30}),
    DigG = graffeo_digraph:wrap(D),

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
    digraph:delete(D).
