-module(graffeo_ets_tests).

-include_lib("eunit/include/eunit.hrl").

%% F-7: wrap/1 lifts a bare digraph handle into #graffeo{}
digraph_wrap_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_edge(D, a, b),
    G = graffeo_ets:wrap(D),
    ?assertEqual(lists:sort([a, b]), lists:sort(graffeo:vertices(G))),
    ?assertEqual([b], graffeo:out_neighbours(G, a)),
    digraph:delete(D).

%% F-6: read half parity with digraph_utils on the same graph
digraph_read_parity_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_vertex(D, c),
    digraph:add_edge(D, a, b),
    digraph:add_edge(D, b, c),
    digraph:add_edge(D, a, c),
    G = graffeo_ets:wrap(D),
    ?assertEqual(
        lists:sort(digraph:vertices(D)),
        lists:sort(graffeo:vertices(G))
    ),
    ?assertEqual(
        lists:sort(digraph:out_neighbours(D, a)),
        lists:sort(graffeo:out_neighbours(G, a))
    ),
    ?assertEqual(
        lists:sort(digraph:in_neighbours(D, c)),
        lists:sort(graffeo:in_neighbours(G, c))
    ),
    ?assertEqual(digraph:in_degree(D, c), graffeo:in_degree(G, c)),
    ?assertEqual(digraph:out_degree(D, a), graffeo:out_degree(G, a)),
    ?assertEqual(digraph:no_edges(D), graffeo:no_edges(G)),
    ?assertEqual(digraph:no_vertices(D), graffeo:no_vertices(G)),
    digraph:delete(D).

%% digraph edge metadata round-trip
digraph_edge_meta_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, x),
    digraph:add_vertex(D, y),
    digraph:add_edge(D, x, y, #{weight => 5}),
    G = graffeo_ets:wrap(D),
    ?assertEqual({ok, #{weight => 5}}, graffeo:edge_meta(G, x, y)),
    ?assertEqual(error, graffeo:edge_meta(G, y, x)),
    digraph:delete(D).

%% digraph vertex label
digraph_vertex_label_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, v1, my_label),
    G = graffeo_ets:wrap(D),
    ?assertEqual({ok, my_label}, graffeo:vertex_label(G, v1)),
    ?assertEqual(error, graffeo:vertex_label(G, nonexistent)),
    digraph:delete(D).

%% new/0 + add_edge smoke test
digraph_new_add_test() ->
    G = graffeo_ets:new(),
    ?assertEqual(0, graffeo:no_vertices(G)),
    ?assertEqual(0, graffeo:no_edges(G)).
