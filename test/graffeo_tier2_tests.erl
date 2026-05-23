-module(graffeo_tier2_tests).
-moduledoc false.

-include_lib("eunit/include/eunit.hrl").

%% F-26: envelope build — new/0's result is directly buildable
digraph_envelope_build_test() ->
    G = graffeo_digraph:new(),
    ok = graffeo_digraph:add_edge(G, a, b, #{weight => 1}),
    ok = graffeo_digraph:add_edge(G, b, c, #{weight => 2}),
    ok = graffeo_digraph:add_vertex(G, b, my_label),
    ?assertEqual(3, graffeo:no_vertices(G)),
    ?assertEqual(2, graffeo:no_edges(G)),
    ?assertEqual({ok, my_label}, graffeo:vertex_label(G, b)),
    {ok, Order} = graffeo:topsort(G),
    ?assert(length(Order) =:= 3),
    graffeo_digraph:delete(G).

%% F-27: unwrap/1 returns the bare digraph; round-trips with wrap/1
digraph_unwrap_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, x),
    G = graffeo_digraph:wrap(D),
    ?assertEqual(D, graffeo_digraph:unwrap(G)),
    digraph:add_vertex(D, y),
    ?assertEqual(lists:sort([x, y]), lists:sort(graffeo:vertices(G))),
    digraph:delete(D).

%% F-28: del_edge/3 removes the From→To edge; counts/neighbours reflect it
digraph_del_edge_test() ->
    G = graffeo_digraph:new(),
    ok = graffeo_digraph:add_edge(G, a, b),
    ok = graffeo_digraph:add_edge(G, b, c),
    ?assertEqual(2, graffeo:no_edges(G)),
    ok = graffeo_digraph:del_edge(G, a, b),
    ?assertEqual(1, graffeo:no_edges(G)),
    ?assertEqual([], graffeo:out_neighbours(G, a)),
    ?assertEqual([], graffeo:in_neighbours(G, b)),
    graffeo_digraph:delete(G).

%% F-28 bonus: del_edge on a wrapped multigraph removes all parallels
digraph_del_edge_parallel_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, x),
    digraph:add_vertex(D, y),
    digraph:add_edge(D, x, y, #{weight => 1}),
    digraph:add_edge(D, x, y, #{weight => 2}),
    digraph:add_edge(D, x, y, #{weight => 3}),
    G = graffeo_digraph:wrap(D),
    ?assertEqual(1, graffeo:no_edges(G)),
    ok = graffeo_digraph:del_edge(G, x, y),
    ?assertEqual(0, graffeo:no_edges(G)),
    ?assertEqual(0, digraph:no_edges(D)),
    digraph:delete(D).

%% F-29: del_vertex/2 removes the vertex and its incident edges
digraph_del_vertex_test() ->
    G = graffeo_digraph:new(),
    ok = graffeo_digraph:add_edge(G, a, b),
    ok = graffeo_digraph:add_edge(G, b, c),
    ok = graffeo_digraph:add_edge(G, c, a),
    ?assertEqual(3, graffeo:no_vertices(G)),
    ok = graffeo_digraph:del_vertex(G, b),
    ?assertEqual(2, graffeo:no_vertices(G)),
    ?assertEqual(1, graffeo:no_edges(G)),
    ?assertEqual([], graffeo:out_neighbours(G, a)),
    ?assertEqual([], graffeo:in_neighbours(G, c)),
    graffeo_digraph:delete(G).

%% F-30: delete/1 frees the underlying handle
digraph_delete_test() ->
    G = graffeo_digraph:new(),
    ok = graffeo_digraph:add_vertex(G, a),
    D = graffeo_digraph:unwrap(G),
    ?assertMatch([_ | _], digraph:info(D)),
    ok = graffeo_digraph:delete(G),
    ?assertError(_, digraph:info(D)).

%% F-31: {handle_only, Op, Backend} raised on non-handle graph
handle_only_guard_test() ->
    MapG = graffeo:new(),
    ?assertError({handle_only, add_vertex, graffeo_map}, graffeo_digraph:add_vertex(MapG, a)),
    ?assertError({handle_only, add_edge, graffeo_map}, graffeo_digraph:add_edge(MapG, a, b)),
    ?assertError({handle_only, del_edge, graffeo_map}, graffeo_digraph:del_edge(MapG, a, b)),
    ?assertError({handle_only, del_vertex, graffeo_map}, graffeo_digraph:del_vertex(MapG, a)),
    ?assertError({handle_only, delete, graffeo_map}, graffeo_digraph:delete(MapG)),
    ?assertError({handle_only, unwrap, graffeo_map}, graffeo_digraph:unwrap(MapG)).

%% F-32: graffeo_digraph no longer declares graffeo_builder; graffeo_map still does
behaviour_declarations_test() ->
    {ok, DigSrc} = file:read_file("src/graffeo_digraph.erl"),
    ?assertEqual(nomatch, binary:match(DigSrc, <<"behaviour(graffeo_builder)">>)),
    {ok, MapSrc} = file:read_file("src/graffeo_map.erl"),
    ?assertNotEqual(nomatch, binary:match(MapSrc, <<"behaviour(graffeo_builder)">>)).
