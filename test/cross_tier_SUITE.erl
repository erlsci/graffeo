-module(cross_tier_SUITE).
-moduledoc """
Cross-tier parity: same edge list, identical results on a Tier-1
value graph, a Tier-2 ETS handle, and a Tier-3 DETS handle.
""".

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

-export([
    topsort_parity/1,
    dijkstra_parity/1,
    bfs_parity/1,
    degree_parity/1,
    read_half_parity/1
]).

all() ->
    [topsort_parity, dijkstra_parity, bfs_parity, degree_parity, read_half_parity].

init_per_testcase(_TC, Config) ->
    Edges = [{a, b, 1}, {b, c, 2}, {a, c, 10}, {c, d, 3}],
    MapG = build_map_graph(Edges),
    {DigraphG, DRef} = build_digraph_graph(Edges),
    DetsG = build_dets_graph(MapG),
    [
        {map_g, MapG},
        {digraph_g, DigraphG},
        {digraph_ref, DRef},
        {dets_g, DetsG},
        {edges, Edges}
        | Config
    ].

end_per_testcase(_TC, Config) ->
    DRef = ?config(digraph_ref, Config),
    digraph:delete(DRef),
    DetsG = ?config(dets_g, Config),
    graffeo_dets:delete(DetsG),
    ok.

topsort_parity(Config) ->
    MapG = ?config(map_g, Config),
    DigraphG = ?config(digraph_g, Config),
    DetsG = ?config(dets_g, Config),
    {ok, MapOrder} = graffeo:topsort(MapG),
    {ok, DigraphOrder} = graffeo:topsort(DigraphG),
    {ok, DetsOrder} = graffeo:topsort(DetsG),
    ?assertEqual(length(MapOrder), length(DigraphOrder)),
    ?assertEqual(length(MapOrder), length(DetsOrder)),
    assert_valid_topsort(MapG, MapOrder),
    assert_valid_topsort(DigraphG, DigraphOrder),
    assert_valid_topsort(DetsG, DetsOrder).

dijkstra_parity(Config) ->
    MapG = ?config(map_g, Config),
    DigraphG = ?config(digraph_g, Config),
    DetsG = ?config(dets_g, Config),
    {MapDist, _} = graffeo:dijkstra(MapG, a),
    {DigDist, _} = graffeo:dijkstra(DigraphG, a),
    {DetsDist, _} = graffeo:dijkstra(DetsG, a),
    Verts = [a, b, c, d],
    lists:foreach(
        fun(V) ->
            ?assertEqual(maps:get(V, MapDist), maps:get(V, DigDist)),
            ?assertEqual(maps:get(V, MapDist), maps:get(V, DetsDist))
        end,
        Verts
    ).

bfs_parity(Config) ->
    MapG = ?config(map_g, Config),
    DigraphG = ?config(digraph_g, Config),
    DetsG = ?config(dets_g, Config),
    MapBFS = lists:sort(graffeo:bfs(MapG, a)),
    DigBFS = lists:sort(graffeo:bfs(DigraphG, a)),
    DetsBFS = lists:sort(graffeo:bfs(DetsG, a)),
    ?assertEqual(MapBFS, DigBFS),
    ?assertEqual(MapBFS, DetsBFS),
    MapBFSIn = lists:sort(graffeo:bfs(MapG, d, #{direction => in})),
    DigBFSIn = lists:sort(graffeo:bfs(DigraphG, d, #{direction => in})),
    DetsBFSIn = lists:sort(graffeo:bfs(DetsG, d, #{direction => in})),
    ?assertEqual(MapBFSIn, DigBFSIn),
    ?assertEqual(MapBFSIn, DetsBFSIn).

degree_parity(Config) ->
    MapG = ?config(map_g, Config),
    DigraphG = ?config(digraph_g, Config),
    DetsG = ?config(dets_g, Config),
    Verts = [a, b, c, d],
    lists:foreach(
        fun(V) ->
            ?assertEqual(graffeo:in_degree(MapG, V), graffeo:in_degree(DigraphG, V)),
            ?assertEqual(graffeo:in_degree(MapG, V), graffeo:in_degree(DetsG, V)),
            ?assertEqual(graffeo:out_degree(MapG, V), graffeo:out_degree(DigraphG, V)),
            ?assertEqual(graffeo:out_degree(MapG, V), graffeo:out_degree(DetsG, V)),
            ?assertEqual(graffeo:degree(MapG, V), graffeo:degree(DigraphG, V)),
            ?assertEqual(graffeo:degree(MapG, V), graffeo:degree(DetsG, V)),
            MapC = graffeo:degree_centrality(MapG, V),
            DigC = graffeo:degree_centrality(DigraphG, V),
            DetsC = graffeo:degree_centrality(DetsG, V),
            ?assert(abs(MapC - DigC) < 0.001),
            ?assert(abs(MapC - DetsC) < 0.001)
        end,
        Verts
    ).

read_half_parity(Config) ->
    MapG = ?config(map_g, Config),
    DigraphG = ?config(digraph_g, Config),
    DetsG = ?config(dets_g, Config),
    ?assertEqual(
        lists:sort(graffeo:vertices(MapG)),
        lists:sort(graffeo:vertices(DigraphG))
    ),
    ?assertEqual(
        lists:sort(graffeo:vertices(MapG)),
        lists:sort(graffeo:vertices(DetsG))
    ),
    ?assertEqual(graffeo:no_vertices(MapG), graffeo:no_vertices(DigraphG)),
    ?assertEqual(graffeo:no_vertices(MapG), graffeo:no_vertices(DetsG)),
    ?assertEqual(graffeo:no_edges(MapG), graffeo:no_edges(DigraphG)),
    ?assertEqual(graffeo:no_edges(MapG), graffeo:no_edges(DetsG)),
    lists:foreach(
        fun(V) ->
            ?assertEqual(
                lists:sort(graffeo:out_neighbours(MapG, V)),
                lists:sort(graffeo:out_neighbours(DigraphG, V))
            ),
            ?assertEqual(
                lists:sort(graffeo:out_neighbours(MapG, V)),
                lists:sort(graffeo:out_neighbours(DetsG, V))
            ),
            ?assertEqual(
                lists:sort(graffeo:in_neighbours(MapG, V)),
                lists:sort(graffeo:in_neighbours(DigraphG, V))
            ),
            ?assertEqual(
                lists:sort(graffeo:in_neighbours(MapG, V)),
                lists:sort(graffeo:in_neighbours(DetsG, V))
            ),
            ?assertEqual(graffeo:edge_meta(MapG, V, V), graffeo:edge_meta(DetsG, V, V)),
            ?assertEqual(graffeo:vertex_label(MapG, V), graffeo:vertex_label(DetsG, V))
        end,
        [a, b, c, d]
    ),
    ?assertEqual(graffeo:edge_meta(MapG, a, b), graffeo:edge_meta(DetsG, a, b)),
    ?assertEqual(graffeo:edge_meta(MapG, b, c), graffeo:edge_meta(DetsG, b, c)).

%%% --- helpers ---

build_map_graph(Edges) ->
    lists:foldl(
        fun({From, To, W}, G) ->
            graffeo:add_edge(G, From, To, #{weight => W})
        end,
        graffeo:new(),
        Edges
    ).

build_digraph_graph(Edges) ->
    D = digraph:new(),
    lists:foreach(
        fun({From, To, W}) ->
            digraph:add_vertex(D, From),
            digraph:add_vertex(D, To),
            digraph:add_edge(D, From, To, #{weight => W})
        end,
        Edges
    ),
    {graffeo_ets:wrap(D), D}.

build_dets_graph(MapG) ->
    Name = "ct_parity_" ++ integer_to_list(erlang:unique_integer([positive])),
    graffeo_dets:from_graph(MapG, Name).

assert_valid_topsort(G, Order) ->
    Pos = maps:from_list(lists:zip(Order, lists:seq(1, length(Order)))),
    lists:foreach(
        fun(V) ->
            Ns = graffeo:out_neighbours(G, V),
            VPos = maps:get(V, Pos),
            lists:foreach(
                fun(N) ->
                    ?assert(maps:get(N, Pos) > VPos)
                end,
                Ns
            )
        end,
        graffeo:vertices(G)
    ).
