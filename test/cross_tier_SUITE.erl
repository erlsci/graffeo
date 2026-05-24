-module(cross_tier_SUITE).
-moduledoc """
Cross-tier parity: same edge list, identical results on a Tier-1
value graph and a Tier-2 digraph handle.
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
    [{map_g, MapG}, {digraph_g, DigraphG}, {digraph_ref, DRef}, {edges, Edges} | Config].

end_per_testcase(_TC, Config) ->
    DRef = ?config(digraph_ref, Config),
    digraph:delete(DRef),
    ok.

%% F-15: topsort parity
topsort_parity(Config) ->
    MapG = ?config(map_g, Config),
    DigraphG = ?config(digraph_g, Config),
    {ok, MapOrder} = graffeo:topsort(MapG),
    {ok, DigraphOrder} = graffeo:topsort(DigraphG),
    ?assertEqual(length(MapOrder), length(DigraphOrder)),
    assert_valid_topsort(MapG, MapOrder),
    assert_valid_topsort(DigraphG, DigraphOrder).

%% F-15: dijkstra parity
dijkstra_parity(Config) ->
    MapG = ?config(map_g, Config),
    DigraphG = ?config(digraph_g, Config),
    {MapDist, _} = graffeo:dijkstra(MapG, a),
    {DigDist, _} = graffeo:dijkstra(DigraphG, a),
    ?assertEqual(maps:get(a, MapDist), maps:get(a, DigDist)),
    ?assertEqual(maps:get(b, MapDist), maps:get(b, DigDist)),
    ?assertEqual(maps:get(c, MapDist), maps:get(c, DigDist)),
    ?assertEqual(maps:get(d, MapDist), maps:get(d, DigDist)).

%% F-15: BFS parity
bfs_parity(Config) ->
    MapG = ?config(map_g, Config),
    DigraphG = ?config(digraph_g, Config),
    MapBFS = lists:sort(graffeo:bfs(MapG, a)),
    DigBFS = lists:sort(graffeo:bfs(DigraphG, a)),
    ?assertEqual(MapBFS, DigBFS),
    MapBFSIn = lists:sort(graffeo:bfs(MapG, d, #{direction => in})),
    DigBFSIn = lists:sort(graffeo:bfs(DigraphG, d, #{direction => in})),
    ?assertEqual(MapBFSIn, DigBFSIn).

%% F-15: degree parity
degree_parity(Config) ->
    MapG = ?config(map_g, Config),
    DigraphG = ?config(digraph_g, Config),
    Verts = [a, b, c, d],
    lists:foreach(
        fun(V) ->
            ?assertEqual(graffeo:in_degree(MapG, V), graffeo:in_degree(DigraphG, V)),
            ?assertEqual(graffeo:out_degree(MapG, V), graffeo:out_degree(DigraphG, V)),
            ?assertEqual(graffeo:degree(MapG, V), graffeo:degree(DigraphG, V)),
            MapC = graffeo:degree_centrality(MapG, V),
            DigC = graffeo:degree_centrality(DigraphG, V),
            ?assert(abs(MapC - DigC) < 0.001)
        end,
        Verts
    ).

%% F-15: read-half parity
read_half_parity(Config) ->
    MapG = ?config(map_g, Config),
    DigraphG = ?config(digraph_g, Config),
    ?assertEqual(
        lists:sort(graffeo:vertices(MapG)),
        lists:sort(graffeo:vertices(DigraphG))
    ),
    ?assertEqual(graffeo:no_vertices(MapG), graffeo:no_vertices(DigraphG)),
    ?assertEqual(graffeo:no_edges(MapG), graffeo:no_edges(DigraphG)),
    lists:foreach(
        fun(V) ->
            ?assertEqual(
                lists:sort(graffeo:out_neighbours(MapG, V)),
                lists:sort(graffeo:out_neighbours(DigraphG, V))
            ),
            ?assertEqual(
                lists:sort(graffeo:in_neighbours(MapG, V)),
                lists:sort(graffeo:in_neighbours(DigraphG, V))
            )
        end,
        [a, b, c, d]
    ).

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
