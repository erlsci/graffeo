-module(graffeo_path_parity_tests).
-moduledoc false.

-include_lib("eunit/include/eunit.hrl").

%%% Parity harness
build_fixture(Edges) ->
    MapG = lists:foldl(
        fun
            ({F, T}, G) -> graffeo:add_edge(G, F, T);
            ({F, T, W}, G) -> graffeo:add_edge(G, F, T, #{weight => W})
        end,
        graffeo:new(),
        Edges
    ),
    D = digraph:new(),
    lists:foreach(
        fun
            ({F, T}) ->
                digraph:add_vertex(D, F),
                digraph:add_vertex(D, T),
                digraph:add_edge(D, F, T);
            ({F, T, W}) ->
                digraph:add_vertex(D, F),
                digraph:add_vertex(D, T),
                digraph:add_edge(D, F, T, #{weight => W})
        end,
        Edges
    ),
    DigG = graffeo_digraph:wrap(D),
    {MapG, DigG, D}.

normalize(L) -> lists:sort(L).
cleanup(D) -> digraph:delete(D).

dag_edges() -> [{a, b}, {b, c}, {c, d}, {a, c}].
cyclic_edges() -> [{a, b}, {b, c}, {c, a}].
loop_edges() -> [{a, a}, {a, b}].

%%% === MUST-5 helper: validate a path ===

is_valid_path(_G, false) ->
    false;
is_valid_path(_G, [_]) ->
    true;
is_valid_path(G, [V, W | Rest]) ->
    lists:member(W, graffeo:out_neighbours(G, V)) andalso
        is_valid_path(G, [W | Rest]).

is_valid_cycle(G, Path) ->
    is_valid_path(G, Path) andalso hd(Path) =:= lists:last(Path).

%%% === M2-15: get_path ===

get_path_test() ->
    {MapG, DigG, D} = build_fixture(dag_edges()),
    StdLib = digraph:get_path(D, a, d),
    Graffeo = graffeo:get_path(DigG, a, d),
    ?assertEqual(StdLib, Graffeo),
    MapResult = graffeo:get_path(MapG, a, d),
    ?assert(is_valid_path(MapG, MapResult)),
    ?assertEqual(a, hd(MapResult)),
    ?assertEqual(d, lists:last(MapResult)),
    ?assertEqual(false, graffeo:get_path(DigG, d, a)),
    ?assertEqual(false, graffeo:get_path(MapG, d, a)),
    cleanup(D).

%%% === M2-16: get_cycle ===

get_cycle_test() ->
    {MapG, DigG, D} = build_fixture(cyclic_edges()),
    StdLib = digraph:get_cycle(D, a),
    Graffeo = graffeo:get_cycle(DigG, a),
    ?assertEqual(StdLib, Graffeo),
    MapCycle = graffeo:get_cycle(MapG, a),
    ?assert(is_valid_cycle(MapG, MapCycle)),
    cleanup(D),
    {MapGD, DigGD, DD} = build_fixture(dag_edges()),
    ?assertEqual(false, graffeo:get_cycle(DigGD, a)),
    ?assertEqual(false, graffeo:get_cycle(MapGD, a)),
    cleanup(DD),
    {MapGL, DigGL, DL} = build_fixture(loop_edges()),
    StdLibLoop = digraph:get_cycle(DL, a),
    ?assertEqual(StdLibLoop, graffeo:get_cycle(DigGL, a)),
    ?assertEqual([a], graffeo:get_cycle(MapGL, a)),
    cleanup(DL).

%%% === M2-17: get_short_path (amended — length parity, not exact) ===

get_short_path_test() ->
    {MapG, DigG, D} = build_fixture(dag_edges()),
    StdLib = digraph:get_short_path(D, a, d),
    Graffeo = graffeo:get_short_path(DigG, a, d),
    ?assertEqual(length(StdLib), length(Graffeo)),
    ?assert(is_valid_path(DigG, Graffeo)),
    ?assertEqual(a, hd(Graffeo)),
    ?assertEqual(d, lists:last(Graffeo)),
    MapResult = graffeo:get_short_path(MapG, a, d),
    ?assert(is_valid_path(MapG, MapResult)),
    ?assertEqual(length(Graffeo), length(MapResult)),
    ?assertEqual(false, graffeo:get_short_path(DigG, d, a)),
    cleanup(D),
    {_MapGC, DigGC, DC} = build_fixture(cyclic_edges()),
    StdLibCycle = digraph:get_short_path(DC, a, a),
    GraffeoCycle = graffeo:get_short_path(DigGC, a, a),
    ?assertEqual(length(StdLibCycle), length(GraffeoCycle)),
    ?assert(is_valid_cycle(DigGC, GraffeoCycle)),
    cleanup(DC).

%%% === M2-18: get_short_cycle ===

get_short_cycle_test() ->
    {_MapG, DigG, D} = build_fixture(cyclic_edges()),
    StdLib = digraph:get_short_cycle(D, a),
    Graffeo = graffeo:get_short_cycle(DigG, a),
    ?assertEqual(length(StdLib), length(Graffeo)),
    ?assert(is_valid_cycle(DigG, Graffeo)),
    cleanup(D),
    {_, DigGD, DD} = build_fixture(dag_edges()),
    ?assertEqual(false, graffeo:get_short_cycle(DigGD, a)),
    cleanup(DD).

%%% === M2-19: source_vertices ===

source_vertices_test() ->
    {MapG, DigG, D} = build_fixture(dag_edges()),
    StdLib = digraph:source_vertices(D),
    Graffeo = graffeo:source_vertices(DigG),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(normalize(graffeo:source_vertices(MapG)), normalize(Graffeo)),
    cleanup(D).

%%% === M2-20: sink_vertices ===

sink_vertices_test() ->
    {MapG, DigG, D} = build_fixture(dag_edges()),
    StdLib = digraph:sink_vertices(D),
    Graffeo = graffeo:sink_vertices(DigG),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(normalize(graffeo:sink_vertices(MapG)), normalize(Graffeo)),
    cleanup(D).

%%% === M2-25: del_vertices ===

del_vertices_test() ->
    G = graffeo_digraph:new(),
    ok = graffeo_digraph:add_edge(G, a, b),
    ok = graffeo_digraph:add_edge(G, b, c),
    ok = graffeo_digraph:add_edge(G, c, d),
    ok = graffeo_digraph:del_vertices(G, [b, c]),
    ?assertEqual(2, graffeo:no_vertices(G)),
    ?assertEqual(0, graffeo:no_edges(G)),
    ?assertEqual(lists:sort([a, d]), lists:sort(graffeo:vertices(G))),
    graffeo_digraph:delete(G),
    MapG = graffeo:new(),
    ?assertError({handle_only, del_vertices, graffeo_map}, graffeo_digraph:del_vertices(MapG, [a])).

%%% === M2-26: del_edges ===

del_edges_test() ->
    G = graffeo_digraph:new(),
    ok = graffeo_digraph:add_edge(G, a, b),
    ok = graffeo_digraph:add_edge(G, b, c),
    ok = graffeo_digraph:add_edge(G, c, d),
    ok = graffeo_digraph:del_edges(G, [{a, b}, {c, d}]),
    ?assertEqual(1, graffeo:no_edges(G)),
    ?assertEqual([c], graffeo:out_neighbours(G, b)),
    graffeo_digraph:delete(G),
    MapG = graffeo:new(),
    ?assertError({handle_only, del_edges, graffeo_map}, graffeo_digraph:del_edges(MapG, [{a, b}])).
