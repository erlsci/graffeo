-module(graffeo_coverage_tests).
-moduledoc false.

-include_lib("eunit/include/eunit.hrl").

%%% --- graffeo facade via digraph backend ---

digraph_facade_vertices_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    G = graffeo_digraph:wrap(D),
    ?assertEqual(lists:sort([a, b]), lists:sort(graffeo:vertices(G))),
    ?assertEqual(2, graffeo:no_vertices(G)),
    ?assertEqual(0, graffeo:no_edges(G)),
    digraph:delete(D).

digraph_facade_edges_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, x),
    digraph:add_vertex(D, y),
    digraph:add_edge(D, x, y, #{weight => 7}),
    G = graffeo_digraph:wrap(D),
    ?assertEqual([y], graffeo:out_neighbours(G, x)),
    ?assertEqual([x], graffeo:in_neighbours(G, y)),
    ?assertEqual(1, graffeo:out_degree(G, x)),
    ?assertEqual(1, graffeo:in_degree(G, y)),
    ?assertEqual(0, graffeo:in_degree(G, x)),
    ?assertEqual(1, graffeo:no_edges(G)),
    ?assertEqual({ok, #{weight => 7}}, graffeo:edge_meta(G, x, y)),
    ?assertEqual(error, graffeo:edge_meta(G, y, x)),
    digraph:delete(D).

digraph_facade_vertex_label_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, k, some_label),
    G = graffeo_digraph:wrap(D),
    ?assertEqual({ok, some_label}, graffeo:vertex_label(G, k)),
    ?assertEqual(error, graffeo:vertex_label(G, nonexistent)),
    digraph:delete(D).

%%% --- graffeo_digraph builder functions ---

digraph_builder_test() ->
    G = graffeo_digraph:new(),
    D = element(3, G),
    ok = graffeo_digraph:add_edge(D, a, b),
    ok = graffeo_digraph:add_edge(D, b, a, #{weight => 5}),
    ok = graffeo_digraph:add_vertex(D, b, my_label),
    ?assertEqual(lists:sort([a, b]), lists:sort(graffeo:vertices(G))),
    ?assertEqual(2, graffeo:no_edges(G)),
    ?assertEqual({ok, my_label}, graffeo:vertex_label(G, b)),
    ?assertEqual({ok, #{weight => 5}}, graffeo:edge_meta(G, b, a)),
    digraph:delete(D).

digraph_edge_meta_not_found_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    G = graffeo_digraph:wrap(D),
    ?assertEqual(error, graffeo:edge_meta(G, a, b)),
    digraph:delete(D).

%%% --- graffeo_conn DFS ---

dfs_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    G3 = graffeo:add_edge(G2, a, c),
    Ref = element(3, G3),
    DFS = graffeo_conn:dfs(graffeo_map, Ref, graffeo_map:vertices(Ref)),
    ?assertEqual(3, length(DFS)),
    ?assert(lists:member(a, DFS)),
    ?assert(lists:member(b, DFS)),
    ?assert(lists:member(c, DFS)).

postorder_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    Ref = element(3, G2),
    PO = graffeo_conn:postorder(graffeo_map, Ref, graffeo_map:vertices(Ref)),
    ?assertEqual(3, length(PO)).

%%% --- graffeo_path edge cases ---

dijkstra_stale_queue_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b, #{weight => 1}),
    G2 = graffeo:add_edge(G1, a, c, #{weight => 2}),
    G3 = graffeo:add_edge(G2, b, c, #{weight => 1}),
    {Dist, _} = graffeo:dijkstra(G3, a),
    ?assertEqual(2, maps:get(c, Dist)).

dijkstra_no_edges_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_vertex(G0, a),
    G2 = graffeo:add_vertex(G1, b),
    {Dist, _} = graffeo:dijkstra(G2, a),
    ?assertEqual(0, maps:get(a, Dist)),
    ?assertEqual(error, maps:find(b, Dist)).

dijkstra_digraph_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_vertex(D, c),
    digraph:add_edge(D, a, b, #{weight => 3}),
    digraph:add_edge(D, b, c, #{weight => 4}),
    G = graffeo_digraph:wrap(D),
    {Dist, _} = graffeo:dijkstra(G, a),
    ?assertEqual(0, maps:get(a, Dist)),
    ?assertEqual(3, maps:get(b, Dist)),
    ?assertEqual(7, maps:get(c, Dist)),
    digraph:delete(D).

dijkstra_custom_cost_digraph_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_edge(D, a, b, #{weight => 10}),
    G = graffeo_digraph:wrap(D),
    CostFun = fun(#{weight := W}) -> W * 2 end,
    {Dist, _} = graffeo:dijkstra(G, a, #{cost => CostFun}),
    ?assertEqual(20, maps:get(b, Dist)),
    digraph:delete(D).

%%% --- graffeo_traverse via digraph ---

bfs_digraph_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_vertex(D, c),
    digraph:add_edge(D, a, b),
    digraph:add_edge(D, b, c),
    G = graffeo_digraph:wrap(D),
    Result = graffeo:bfs(G, a),
    ?assertEqual({a, 0}, lists:keyfind(a, 1, Result)),
    ?assertEqual({b, 1}, lists:keyfind(b, 1, Result)),
    ?assertEqual({c, 2}, lists:keyfind(c, 1, Result)),
    digraph:delete(D).

bfs_both_direction_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, c, b),
    Result = graffeo:bfs(G2, b, #{direction => both}),
    Verts = [V || {V, _} <- Result],
    ?assert(lists:member(a, Verts)),
    ?assert(lists:member(c, Verts)).

degree_centrality_single_vertex_test() ->
    G = graffeo:add_vertex(graffeo:new(), a),
    ?assertEqual(0.0, graffeo:degree_centrality(G, a)).

degree_digraph_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_edge(D, a, b),
    G = graffeo_digraph:wrap(D),
    ?assertEqual(1, graffeo:degree(G, a)),
    ?assertEqual(1, graffeo:degree(G, b)),
    digraph:delete(D).

top_k_digraph_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_vertex(D, c),
    digraph:add_edge(D, a, b),
    digraph:add_edge(D, a, c),
    G = graffeo_digraph:wrap(D),
    [{a, 2}] = graffeo:top_k_by_degree(G, 1),
    digraph:delete(D).

%%% --- topsort via digraph ---

topsort_digraph_cycle_test() ->
    D = digraph:new([cyclic]),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_edge(D, a, b),
    digraph:add_edge(D, b, a),
    G = graffeo_digraph:wrap(D),
    ?assertEqual(false, graffeo:topsort(G)),
    digraph:delete(D).

%%% --- graffeo_map edge_meta error paths ---

map_edge_meta_no_source_test() ->
    G = graffeo:new(),
    ?assertEqual(error, graffeo:edge_meta(G, x, y)).

map_vertex_label_missing_test() ->
    G = graffeo:new(),
    ?assertEqual(error, graffeo:vertex_label(G, nonexistent)).

%%% --- graffeo_path edge_cost with missing meta ---

dijkstra_default_weight_edges_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    {Dist, _} = graffeo:dijkstra(G2, a),
    ?assertEqual(1, maps:get(b, Dist)),
    ?assertEqual(2, maps:get(c, Dist)).
