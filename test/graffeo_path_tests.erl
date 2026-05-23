-module(graffeo_path_tests).

-include_lib("eunit/include/eunit.hrl").

%% F-10: dijkstra/2 correct distances on a known weighted graph
%%   a --1--> b --2--> c
%%   a --10-> c
%% shortest a→c is 3 (via b), not 10
dijkstra_default_cost_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b, #{weight => 1}),
    G2 = graffeo:add_edge(G1, b, c, #{weight => 2}),
    G3 = graffeo:add_edge(G2, a, c, #{weight => 10}),
    {Dist, Prev} = graffeo:dijkstra(G3, a),
    ?assertEqual(0, maps:get(a, Dist)),
    ?assertEqual(1, maps:get(b, Dist)),
    ?assertEqual(3, maps:get(c, Dist)),
    ?assertEqual(a, maps:get(b, Prev)),
    ?assertEqual(b, maps:get(c, Prev)).

%% F-11: dijkstra/3 honours a custom cost fun (inverted-weight)
%% With inverted cost, high-weight edges are cheap.
%% a→b (w=10, cost=0.1), b→c (w=10, cost=0.1), total=0.2
%% a→c (w=1, cost=1.0)
%% So cheapest a→c is via b at cost 0.2, not direct at cost 1.0.
dijkstra_custom_cost_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b, #{weight => 10}),
    G2 = graffeo:add_edge(G1, b, c, #{weight => 10}),
    G3 = graffeo:add_edge(G2, a, c, #{weight => 1}),
    InvertedCost = fun(#{weight := W}) -> 1 / max(W, 0.001) end,
    {Dist, Prev} = graffeo:dijkstra(G3, a, #{cost => InvertedCost}),
    ?assertEqual(0, maps:get(a, Dist)),
    ?assert(abs(maps:get(b, Dist) - 0.1) < 0.001),
    ?assert(abs(maps:get(c, Dist) - 0.2) < 0.001),
    ?assertEqual(b, maps:get(c, Prev)).

%% single vertex, no edges
dijkstra_single_test() ->
    G = graffeo:add_vertex(graffeo:new(), x),
    {Dist, Prev} = graffeo:dijkstra(G, x),
    ?assertEqual(0, maps:get(x, Dist)),
    ?assertEqual(#{}, Prev).

%% unreachable vertex
dijkstra_unreachable_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_vertex(G1, c),
    {Dist, _Prev} = graffeo:dijkstra(G2, a),
    ?assertEqual(error, maps:find(c, Dist)).
