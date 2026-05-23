-module(graffeo_astar_tests).
-moduledoc false.

-include_lib("eunit/include/eunit.hrl").

%%% M2-24: astar/3,4

%% Known weighted graph: a--1-->b--2-->c--3-->d, a--10-->d
%% Shortest a→d is via b,c: cost 6 (not direct 10)
astar_default_cost_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b, #{weight => 1}),
    G2 = graffeo:add_edge(G1, b, c, #{weight => 2}),
    G3 = graffeo:add_edge(G2, c, d, #{weight => 3}),
    G4 = graffeo:add_edge(G3, a, d, #{weight => 10}),
    {ok, Path, Cost} = graffeo:astar(G4, a, d),
    ?assertEqual(6, Cost),
    ?assertEqual(a, hd(Path)),
    ?assertEqual(d, lists:last(Path)),
    ?assertEqual(4, length(Path)).

%% Default heuristic == Dijkstra: astar cost matches dijkstra distance
astar_equals_dijkstra_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b, #{weight => 1}),
    G2 = graffeo:add_edge(G1, b, c, #{weight => 2}),
    G3 = graffeo:add_edge(G2, a, c, #{weight => 10}),
    {Dist, _} = graffeo:dijkstra(G3, a),
    {ok, _, AstarCost} = graffeo:astar(G3, a, c),
    ?assertEqual(maps:get(c, Dist), AstarCost).

%% Custom cost: inverted weight (high weight = cheap)
astar_inverted_cost_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b, #{weight => 10}),
    G2 = graffeo:add_edge(G1, b, c, #{weight => 10}),
    G3 = graffeo:add_edge(G2, a, c, #{weight => 1}),
    InvCost = fun(#{weight := W}) -> 1 / max(W, 1.0e-9) end,
    {ok, Path, Cost} = graffeo:astar(G3, a, c, #{cost => InvCost}),
    ?assert(Cost < 0.5),
    ?assertEqual(a, hd(Path)),
    ?assertEqual(c, lists:last(Path)),
    ?assertEqual([a, b, c], Path).

%% Unreachable target → none
astar_unreachable_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_vertex(G1, c),
    ?assertEqual(none, graffeo:astar(G2, a, c)).

%% With a heuristic
astar_with_heuristic_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b, #{weight => 1}),
    G2 = graffeo:add_edge(G1, b, c, #{weight => 1}),
    G3 = graffeo:add_edge(G2, a, c, #{weight => 5}),
    H = fun
        (c) -> 0;
        (b) -> 1;
        (a) -> 2;
        (_) -> 0
    end,
    {ok, Path, Cost} = graffeo:astar(G3, a, c, #{heuristic => H}),
    ?assertEqual(2, Cost),
    ?assertEqual([a, b, c], Path).

%% Cross-tier parity: same result on map and digraph backends
astar_cross_tier_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b, #{weight => 3}),
    G2 = graffeo:add_edge(G1, b, c, #{weight => 4}),
    G3 = graffeo:add_edge(G2, a, c, #{weight => 10}),
    MapResult = graffeo:astar(G3, a, c),
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_vertex(D, c),
    digraph:add_edge(D, a, b, #{weight => 3}),
    digraph:add_edge(D, b, c, #{weight => 4}),
    digraph:add_edge(D, a, c, #{weight => 10}),
    DigG = graffeo_digraph:wrap(D),
    DigResult = graffeo:astar(DigG, a, c),
    ?assertEqual(MapResult, DigResult),
    digraph:delete(D).

%% Single vertex, source == target
astar_source_is_target_test() ->
    G = graffeo:add_vertex(graffeo:new(), a),
    {ok, [a], 0} = graffeo:astar(G, a, a).
