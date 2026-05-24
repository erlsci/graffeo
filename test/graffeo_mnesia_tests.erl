-module(graffeo_mnesia_tests).
-moduledoc false.

-include_lib("eunit/include/eunit.hrl").

%%% === Lifecycle ===

new_delete_test() ->
    G = graffeo_mnesia:new(),
    ?assertEqual(0, graffeo:no_vertices(G)),
    ?assertEqual(0, graffeo:no_edges(G)),
    graffeo_mnesia:delete(G).

open_close_reopen_test() ->
    Name = "test_open_" ++ integer_to_list(erlang:unique_integer([positive])),
    G = graffeo_mnesia:open(Name),
    graffeo_mnesia:add_edge(G, a, b, #{weight => 42}),
    graffeo_mnesia:close(G),
    G2 = graffeo_mnesia:open(Name),
    ?assertEqual(2, graffeo:no_vertices(G2)),
    ?assertEqual({ok, #{weight => 42}}, graffeo:edge_meta(G2, a, b)),
    graffeo_mnesia:delete(G2).

open_binary_name_test() ->
    Name = <<"test_bin_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    G = graffeo_mnesia:open(Name),
    graffeo_mnesia:add_vertex(G, x),
    ?assertEqual(1, graffeo:no_vertices(G)),
    graffeo_mnesia:delete(G).

open_with_ram_copies_test() ->
    Name = "test_ram_" ++ integer_to_list(erlang:unique_integer([positive])),
    G = graffeo_mnesia:open(Name, #{storage => ram_copies}),
    graffeo_mnesia:add_edge(G, a, b),
    ?assertEqual(2, graffeo:no_vertices(G)),
    graffeo_mnesia:delete(G).

%%% === Mutation ===

add_vertex_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_vertex(G, a),
    graffeo_mnesia:add_vertex(G, b, my_label),
    ?assertEqual(2, graffeo:no_vertices(G)),
    ?assertEqual({ok, undefined}, graffeo:vertex_label(G, a)),
    ?assertEqual({ok, my_label}, graffeo:vertex_label(G, b)),
    graffeo_mnesia:delete(G).

add_edge_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b, #{weight => 1}),
    graffeo_mnesia:add_edge(G, b, c),
    ?assertEqual(3, graffeo:no_vertices(G)),
    ?assertEqual(2, graffeo:no_edges(G)),
    ?assertEqual({ok, #{weight => 1}}, graffeo:edge_meta(G, a, b)),
    graffeo_mnesia:delete(G).

add_edge_overwrites_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b, #{weight => 1}),
    graffeo_mnesia:add_edge(G, a, b, #{weight => 99}),
    ?assertEqual(1, graffeo:no_edges(G)),
    ?assertEqual({ok, #{weight => 99}}, graffeo:edge_meta(G, a, b)),
    graffeo_mnesia:delete(G).

del_vertex_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b),
    graffeo_mnesia:add_edge(G, b, c),
    graffeo_mnesia:del_vertex(G, b),
    ?assertEqual(2, graffeo:no_vertices(G)),
    ?assertEqual(0, graffeo:no_edges(G)),
    graffeo_mnesia:delete(G).

del_vertices_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b),
    graffeo_mnesia:add_edge(G, b, c),
    graffeo_mnesia:del_vertices(G, [a, c]),
    ?assertEqual(1, graffeo:no_vertices(G)),
    graffeo_mnesia:delete(G).

del_edge_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b),
    graffeo_mnesia:add_edge(G, b, c),
    graffeo_mnesia:del_edge(G, a, b),
    ?assertEqual(3, graffeo:no_vertices(G)),
    ?assertEqual(1, graffeo:no_edges(G)),
    graffeo_mnesia:delete(G).

del_edges_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b),
    graffeo_mnesia:add_edge(G, b, c),
    graffeo_mnesia:del_edges(G, [{a, b}, {b, c}]),
    ?assertEqual(0, graffeo:no_edges(G)),
    graffeo_mnesia:delete(G).

%%% === Read-half ===

vertices_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b),
    graffeo_mnesia:add_vertex(G, c),
    ?assertEqual([a, b, c], lists:sort(graffeo:vertices(G))),
    graffeo_mnesia:delete(G).

neighbours_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b),
    graffeo_mnesia:add_edge(G, a, c),
    graffeo_mnesia:add_edge(G, d, a),
    ?assertEqual(lists:sort([b, c]), lists:sort(graffeo:out_neighbours(G, a))),
    ?assertEqual([d], graffeo:in_neighbours(G, a)),
    ?assertEqual(2, graffeo:out_degree(G, a)),
    ?assertEqual(1, graffeo:in_degree(G, a)),
    graffeo_mnesia:delete(G).

edge_meta_missing_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_vertex(G, a),
    ?assertEqual(error, graffeo:edge_meta(G, a, b)),
    graffeo_mnesia:delete(G).

vertex_label_missing_test() ->
    G = graffeo_mnesia:new(),
    ?assertEqual(error, graffeo:vertex_label(G, nonexistent)),
    graffeo_mnesia:delete(G).

%%% === Algorithms over Mnesia ===

topsort_mnesia_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b),
    graffeo_mnesia:add_edge(G, b, c),
    graffeo_mnesia:add_edge(G, a, c),
    {ok, Order} = graffeo:topsort(G),
    ?assert(pos(a, Order) < pos(b, Order)),
    ?assert(pos(b, Order) < pos(c, Order)),
    graffeo_mnesia:delete(G).

dijkstra_mnesia_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b, #{weight => 1}),
    graffeo_mnesia:add_edge(G, b, c, #{weight => 2}),
    graffeo_mnesia:add_edge(G, a, c, #{weight => 10}),
    graffeo_mnesia:add_edge(G, c, d, #{weight => 3}),
    {Dist, _} = graffeo:dijkstra(G, a),
    ?assertEqual(0, maps:get(a, Dist)),
    ?assertEqual(1, maps:get(b, Dist)),
    ?assertEqual(3, maps:get(c, Dist)),
    ?assertEqual(6, maps:get(d, Dist)),
    graffeo_mnesia:delete(G).

bfs_mnesia_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b),
    graffeo_mnesia:add_edge(G, b, c),
    R = graffeo:bfs(G, a),
    ?assertEqual(3, length(R)),
    graffeo_mnesia:delete(G).

components_mnesia_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b),
    graffeo_mnesia:add_edge(G, c, d),
    Comps = graffeo:components(G),
    ?assertEqual(2, length(Comps)),
    graffeo_mnesia:delete(G).

%%% === Transactions ===

transaction_atomic_mutation_test() ->
    G = graffeo_mnesia:new(),
    {atomic, ok} = graffeo_mnesia:transaction(fun() ->
        graffeo_mnesia:add_edge(G, a, b, #{weight => 1}),
        graffeo_mnesia:add_edge(G, b, c, #{weight => 2}),
        ok
    end),
    ?assertEqual(3, graffeo:no_vertices(G)),
    ?assertEqual(2, graffeo:no_edges(G)),
    ?assertEqual({ok, #{weight => 1}}, graffeo:edge_meta(G, a, b)),
    graffeo_mnesia:delete(G).

transaction_consistent_read_test() ->
    G = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(G, a, b),
    graffeo_mnesia:add_edge(G, b, c),
    graffeo_mnesia:add_edge(G, a, c),
    {atomic, {ok, Order}} = graffeo_mnesia:transaction(fun() ->
        graffeo:topsort(G)
    end),
    ?assertEqual(3, length(Order)),
    graffeo_mnesia:delete(G).

transaction_dirty_parity_test() ->
    GDirty = graffeo_mnesia:new(),
    graffeo_mnesia:add_edge(GDirty, a, b, #{weight => 1}),
    graffeo_mnesia:add_edge(GDirty, b, c, #{weight => 2}),
    graffeo_mnesia:add_edge(GDirty, a, c, #{weight => 10}),

    GTxn = graffeo_mnesia:new(),
    {atomic, ok} = graffeo_mnesia:transaction(fun() ->
        graffeo_mnesia:add_edge(GTxn, a, b, #{weight => 1}),
        graffeo_mnesia:add_edge(GTxn, b, c, #{weight => 2}),
        graffeo_mnesia:add_edge(GTxn, a, c, #{weight => 10}),
        ok
    end),

    ?assertEqual(
        lists:sort(graffeo:vertices(GDirty)),
        lists:sort(graffeo:vertices(GTxn))
    ),
    ?assertEqual(graffeo:no_edges(GDirty), graffeo:no_edges(GTxn)),
    {DirtyDist, _} = graffeo:dijkstra(GDirty, a),
    {TxnDist, _} = graffeo:dijkstra(GTxn, a),
    ?assertEqual(DirtyDist, TxnDist),

    graffeo_mnesia:delete(GDirty),
    graffeo_mnesia:delete(GTxn).

%%% === copy/2 ===

copy_map_to_mnesia_test() ->
    M = graffeo:new(),
    M1 = graffeo:add_edge(M, x, y, #{weight => 5}),
    M2 = graffeo:add_edge(M1, y, z, #{weight => 3}),
    M3 = graffeo:add_vertex(M2, w, labelled),
    Name = "test_copy_" ++ integer_to_list(erlang:unique_integer([positive])),
    G = graffeo_mnesia:open(Name),
    graffeo:copy(M3, G),
    ?assertEqual(
        lists:sort(graffeo:vertices(M3)),
        lists:sort(graffeo:vertices(G))
    ),
    ?assertEqual(graffeo:no_edges(M3), graffeo:no_edges(G)),
    ?assertEqual({ok, #{weight => 5}}, graffeo:edge_meta(G, x, y)),
    ?assertEqual({ok, labelled}, graffeo:vertex_label(G, w)),
    graffeo_mnesia:delete(G).

%%% === Constructive ops raise ===

empty_like_raises_test() ->
    G = graffeo_mnesia:new(),
    ?assertError(
        {unsupported_on_backend, empty_like, graffeo_mnesia},
        graffeo_mnesia:empty_like(G)
    ),
    graffeo_mnesia:delete(G).

handle_only_raises_test() ->
    M = graffeo:new(),
    ?assertError(
        {handle_only, add_vertex, graffeo_map},
        graffeo_mnesia:add_vertex(M, x)
    ).

%%% === Helpers ===

pos(X, List) -> pos(X, List, 1).
pos(X, [X | _], N) -> N;
pos(X, [_ | T], N) -> pos(X, T, N + 1).
