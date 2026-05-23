-module(graffeo_map_tests).

-include_lib("eunit/include/eunit.hrl").

%% F-3: immutability — op returns new graph, original unchanged
map_immutability_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_vertex(G0, a),
    ?assertEqual([], graffeo:vertices(G0)),
    ?assertEqual([a], graffeo:vertices(G1)),
    G2 = graffeo:add_edge(G1, a, b),
    ?assertEqual([a], graffeo:vertices(G1)),
    ?assertEqual(0, graffeo:no_edges(G1)),
    ?assertEqual(1, graffeo:no_edges(G2)).

%% F-4: labels + edge weights round-trip
map_label_weight_roundtrip_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_vertex(G0, x, my_label),
    ?assertEqual({ok, my_label}, graffeo:vertex_label(G1, x)),
    G2 = graffeo:add_edge(G1, x, y, #{weight => 3.5, label => road}),
    ?assertEqual({ok, #{weight => 3.5, label => road}}, graffeo:edge_meta(G2, x, y)),
    ?assertEqual(error, graffeo:edge_meta(G2, y, x)).

%% F-5: reverse adjacency — in_neighbours / in_degree
map_reverse_adjacency_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, c, b),
    ?assertEqual(lists:sort([a, c]), lists:sort(graffeo:in_neighbours(G2, b))),
    ?assertEqual(2, graffeo:in_degree(G2, b)),
    ?assertEqual(0, graffeo:in_degree(G2, a)),
    ?assertEqual([], graffeo:in_neighbours(G2, a)).

%% basic vertex/edge counting
counts_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    ?assertEqual(3, graffeo:no_vertices(G2)),
    ?assertEqual(2, graffeo:no_edges(G2)).

%% out_neighbours
out_neighbours_test() ->
    G = graffeo:add_edge(graffeo:add_edge(graffeo:new(), a, b), a, c),
    ?assertEqual(lists:sort([b, c]), lists:sort(graffeo:out_neighbours(G, a))),
    ?assertEqual([], graffeo:out_neighbours(G, c)).

%% degree functions
degree_test() ->
    G = graffeo:add_edge(graffeo:add_edge(graffeo:new(), a, b), a, c),
    ?assertEqual(2, graffeo:out_degree(G, a)),
    ?assertEqual(0, graffeo:out_degree(G, b)),
    ?assertEqual(1, graffeo:in_degree(G, b)).

%% default weight is 1
default_weight_test() ->
    G = graffeo:add_edge(graffeo:new(), a, b),
    ?assertEqual({ok, #{weight => 1}}, graffeo:edge_meta(G, a, b)).

%% vertex with default label
default_label_test() ->
    G = graffeo:add_vertex(graffeo:new(), x),
    ?assertEqual({ok, undefined}, graffeo:vertex_label(G, x)).
