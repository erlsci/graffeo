-module(graffeo_dets_tests).
-moduledoc false.

-include_lib("eunit/include/eunit.hrl").

%%% === Lifecycle ===

new_delete_test() ->
    G = graffeo_dets:new(),
    ?assertEqual(0, graffeo:no_vertices(G)),
    ?assertEqual(0, graffeo:no_edges(G)),
    graffeo_dets:delete(G).

open_close_reopen_test() ->
    Name = "test_open_" ++ integer_to_list(erlang:unique_integer([positive])),
    G = graffeo_dets:open(Name),
    graffeo_dets:add_edge(G, a, b, #{weight => 42}),
    graffeo_dets:close(G),
    G2 = graffeo_dets:open(Name),
    ?assertEqual(2, graffeo:no_vertices(G2)),
    ?assertEqual({ok, #{weight => 42}}, graffeo:edge_meta(G2, a, b)),
    graffeo_dets:delete(G2).

open_binary_name_test() ->
    Name = <<"test_bin_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    G = graffeo_dets:open(Name),
    graffeo_dets:add_vertex(G, x),
    ?assertEqual(1, graffeo:no_vertices(G)),
    graffeo_dets:delete(G).

%%% === Mutation ===

add_vertex_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_vertex(G, a),
    graffeo_dets:add_vertex(G, b, my_label),
    ?assertEqual(2, graffeo:no_vertices(G)),
    ?assertEqual({ok, undefined}, graffeo:vertex_label(G, a)),
    ?assertEqual({ok, my_label}, graffeo:vertex_label(G, b)),
    graffeo_dets:delete(G).

add_edge_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b, #{weight => 1}),
    graffeo_dets:add_edge(G, b, c),
    ?assertEqual(3, graffeo:no_vertices(G)),
    ?assertEqual(2, graffeo:no_edges(G)),
    ?assertEqual({ok, #{weight => 1}}, graffeo:edge_meta(G, a, b)),
    graffeo_dets:delete(G).

add_edge_overwrites_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b, #{weight => 1}),
    graffeo_dets:add_edge(G, a, b, #{weight => 99}),
    ?assertEqual(1, graffeo:no_edges(G)),
    ?assertEqual({ok, #{weight => 99}}, graffeo:edge_meta(G, a, b)),
    graffeo_dets:delete(G).

del_vertex_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b),
    graffeo_dets:add_edge(G, b, c),
    graffeo_dets:del_vertex(G, b),
    ?assertEqual(2, graffeo:no_vertices(G)),
    ?assertEqual(0, graffeo:no_edges(G)),
    graffeo_dets:delete(G).

del_vertices_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b),
    graffeo_dets:add_edge(G, b, c),
    graffeo_dets:del_vertices(G, [a, c]),
    ?assertEqual(1, graffeo:no_vertices(G)),
    graffeo_dets:delete(G).

del_edge_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b),
    graffeo_dets:add_edge(G, b, c),
    graffeo_dets:del_edge(G, a, b),
    ?assertEqual(3, graffeo:no_vertices(G)),
    ?assertEqual(1, graffeo:no_edges(G)),
    graffeo_dets:delete(G).

del_edges_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b),
    graffeo_dets:add_edge(G, b, c),
    graffeo_dets:del_edges(G, [{a, b}, {b, c}]),
    ?assertEqual(0, graffeo:no_edges(G)),
    graffeo_dets:delete(G).

%%% === Read-half ===

vertices_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b),
    graffeo_dets:add_vertex(G, c),
    Vs = lists:sort(graffeo:vertices(G)),
    ?assertEqual([a, b, c], Vs),
    graffeo_dets:delete(G).

neighbours_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b),
    graffeo_dets:add_edge(G, a, c),
    graffeo_dets:add_edge(G, d, a),
    ?assertEqual(lists:sort([b, c]), lists:sort(graffeo:out_neighbours(G, a))),
    ?assertEqual([d], graffeo:in_neighbours(G, a)),
    ?assertEqual(2, graffeo:out_degree(G, a)),
    ?assertEqual(1, graffeo:in_degree(G, a)),
    graffeo_dets:delete(G).

edge_meta_missing_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_vertex(G, a),
    ?assertEqual(error, graffeo:edge_meta(G, a, b)),
    graffeo_dets:delete(G).

vertex_label_missing_test() ->
    G = graffeo_dets:new(),
    ?assertEqual(error, graffeo:vertex_label(G, nonexistent)),
    graffeo_dets:delete(G).

%%% === Algorithms over DETS ===

topsort_dets_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b),
    graffeo_dets:add_edge(G, b, c),
    graffeo_dets:add_edge(G, a, c),
    {ok, Order} = graffeo:topsort(G),
    ?assert(pos(a, Order) < pos(b, Order)),
    ?assert(pos(b, Order) < pos(c, Order)),
    graffeo_dets:delete(G).

dijkstra_dets_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b, #{weight => 1}),
    graffeo_dets:add_edge(G, b, c, #{weight => 2}),
    graffeo_dets:add_edge(G, a, c, #{weight => 10}),
    graffeo_dets:add_edge(G, c, d, #{weight => 3}),
    {Dist, _} = graffeo:dijkstra(G, a),
    ?assertEqual(0, maps:get(a, Dist)),
    ?assertEqual(1, maps:get(b, Dist)),
    ?assertEqual(3, maps:get(c, Dist)),
    ?assertEqual(6, maps:get(d, Dist)),
    graffeo_dets:delete(G).

components_dets_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b),
    graffeo_dets:add_edge(G, c, d),
    Comps = graffeo:components(G),
    ?assertEqual(2, length(Comps)),
    graffeo_dets:delete(G).

bfs_dets_test() ->
    G = graffeo_dets:new(),
    graffeo_dets:add_edge(G, a, b),
    graffeo_dets:add_edge(G, b, c),
    R = graffeo:bfs(G, a),
    ?assertEqual(3, length(R)),
    graffeo_dets:delete(G).

%%% === copy/2 ===

copy_map_to_dets_test() ->
    M = graffeo:new(),
    M1 = graffeo:add_edge(M, x, y, #{weight => 5}),
    M2 = graffeo:add_edge(M1, y, z, #{weight => 3}),
    M3 = graffeo:add_vertex(M2, w, labelled),
    D = graffeo_dets:from_graph(
        M3,
        "test_copy_" ++
            integer_to_list(erlang:unique_integer([positive]))
    ),
    ?assertEqual(
        lists:sort(graffeo:vertices(M3)),
        lists:sort(graffeo:vertices(D))
    ),
    ?assertEqual(graffeo:no_edges(M3), graffeo:no_edges(D)),
    ?assertEqual({ok, #{weight => 5}}, graffeo:edge_meta(D, x, y)),
    ?assertEqual({ok, labelled}, graffeo:vertex_label(D, w)),
    graffeo_dets:delete(D).

copy_dets_to_ets_test() ->
    D = graffeo_dets:new(),
    graffeo_dets:add_edge(D, a, b, #{weight => 1}),
    E = graffeo_ets:new(),
    graffeo:copy(D, E),
    ?assertEqual(
        lists:sort(graffeo:vertices(D)),
        lists:sort(graffeo:vertices(E))
    ),
    ?assertEqual(graffeo:no_edges(D), graffeo:no_edges(E)),
    ?assertEqual({ok, #{weight => 1}}, graffeo:edge_meta(E, a, b)),
    graffeo_dets:delete(D),
    graffeo_ets:delete(E).

%%% === 3-way parity ===

three_way_parity_test() ->
    M = graffeo:new(),
    M1 = graffeo:add_edge(M, a, b, #{weight => 1}),
    M2 = graffeo:add_edge(M1, b, c, #{weight => 2}),
    M3 = graffeo:add_edge(M2, a, c, #{weight => 10}),
    M4 = graffeo:add_edge(M3, c, d, #{weight => 3}),

    E = graffeo_ets:new(),
    graffeo:copy(M4, E),

    D = graffeo_dets:new(),
    graffeo:copy(M4, D),

    %% Vertices
    MVs = lists:sort(graffeo:vertices(M4)),
    EVs = lists:sort(graffeo:vertices(E)),
    DVs = lists:sort(graffeo:vertices(D)),
    ?assertEqual(MVs, EVs),
    ?assertEqual(MVs, DVs),

    %% Edge count
    ?assertEqual(graffeo:no_edges(M4), graffeo:no_edges(E)),
    ?assertEqual(graffeo:no_edges(M4), graffeo:no_edges(D)),

    %% Dijkstra
    {MDist, _} = graffeo:dijkstra(M4, a),
    {EDist, _} = graffeo:dijkstra(E, a),
    {DDist, _} = graffeo:dijkstra(D, a),
    ?assertEqual(MDist, EDist),
    ?assertEqual(MDist, DDist),

    %% Topsort
    {ok, MOrder} = graffeo:topsort(M4),
    {ok, EOrder} = graffeo:topsort(E),
    {ok, DOrder} = graffeo:topsort(D),
    ?assertEqual(length(MOrder), length(EOrder)),
    ?assertEqual(length(MOrder), length(DOrder)),

    graffeo_ets:delete(E),
    graffeo_dets:delete(D).

%%% === Constructive ops raise ===

empty_like_raises_test() ->
    G = graffeo_dets:new(),
    ?assertError(
        {unsupported_on_backend, empty_like, graffeo_dets},
        graffeo_dets:empty_like(G)
    ),
    graffeo_dets:delete(G).

handle_only_raises_test() ->
    M = graffeo:new(),
    ?assertError(
        {handle_only, add_vertex, graffeo_map},
        graffeo_dets:add_vertex(M, x)
    ).

%%% === Helpers ===

pos(X, List) -> pos(X, List, 1).
pos(X, [X | _], N) -> N;
pos(X, [_ | T], N) -> pos(X, T, N + 1).
