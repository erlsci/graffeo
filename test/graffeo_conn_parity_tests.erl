-module(graffeo_conn_parity_tests).
-moduledoc false.

-include_lib("eunit/include/eunit.hrl").

%%% === Parity-test harness ===
%%% Two comparisons with different equality rules:
%%% 1. Stdlib parity (exact): graffeo result on digraph backend =:= digraph_utils result
%%% 2. Cross-tier parity (normalized): map backend result == digraph backend result after sort

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

normalize(List) when is_list(List) ->
    case List of
        [[_ | _] | _] -> lists:sort([lists:sort(L) || L <- List]);
        _ -> lists:sort(List)
    end.

cleanup(D) -> digraph:delete(D).

%%% === Fixture graphs ===
%%% DAG: a→b→c→d, a→c
dag_edges() -> [{a, b}, {b, c}, {c, d}, {a, c}].
%%% Cyclic: a→b→c→a, d→e
cyclic_edges() -> [{a, b}, {b, c}, {c, a}, {d, e}].
%%% Self-loop: a→a, a→b
loop_edges() -> [{a, a}, {a, b}].
%%% Tree (undirected sense): a→b, a→c
tree_edges() -> [{a, b}, {a, c}].
%%% Arborescence: a→b, a→c, b→d
arb_edges() -> [{a, b}, {a, c}, {b, d}].
%%% Disconnected: a→b, c→d
disconnected_edges() -> [{a, b}, {c, d}].

%%% === M2-1: components ===

components_test() ->
    {MapG, DigG, D} = build_fixture(disconnected_edges()),
    StdLib = digraph_utils:components(D),
    Graffeo = graffeo:components(DigG),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(normalize(graffeo:components(MapG)), normalize(Graffeo)),
    cleanup(D).

%%% === M2-2: strong_components ===

strong_components_test() ->
    {MapG, DigG, D} = build_fixture(cyclic_edges()),
    StdLib = digraph_utils:strong_components(D),
    Graffeo = graffeo:strong_components(DigG),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(normalize(graffeo:strong_components(MapG)), normalize(Graffeo)),
    cleanup(D).

%%% === M2-3: cyclic_strong_components ===

cyclic_strong_components_test() ->
    {MapG, DigG, D} = build_fixture(cyclic_edges()),
    StdLib = digraph_utils:cyclic_strong_components(D),
    Graffeo = graffeo:cyclic_strong_components(DigG),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(
        normalize(graffeo:cyclic_strong_components(MapG)), normalize(Graffeo)
    ),
    cleanup(D).

%%% === M2-4: reachable ===

reachable_test() ->
    {MapG, DigG, D} = build_fixture(dag_edges()),
    StdLib = digraph_utils:reachable([a], D),
    Graffeo = graffeo:reachable(DigG, [a]),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(normalize(graffeo:reachable(MapG, [a])), normalize(Graffeo)),
    cleanup(D).

%%% === M2-5: reachable_neighbours ===

reachable_neighbours_test() ->
    {MapG, DigG, D} = build_fixture(dag_edges()),
    StdLib = digraph_utils:reachable_neighbours([a], D),
    Graffeo = graffeo:reachable_neighbours(DigG, [a]),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(
        normalize(graffeo:reachable_neighbours(MapG, [a])), normalize(Graffeo)
    ),
    cleanup(D).

%%% === M2-6: reaching ===

reaching_test() ->
    {MapG, DigG, D} = build_fixture(dag_edges()),
    StdLib = digraph_utils:reaching([d], D),
    Graffeo = graffeo:reaching(DigG, [d]),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(normalize(graffeo:reaching(MapG, [d])), normalize(Graffeo)),
    cleanup(D).

%%% === M2-7: reaching_neighbours ===

reaching_neighbours_test() ->
    {MapG, DigG, D} = build_fixture(dag_edges()),
    StdLib = digraph_utils:reaching_neighbours([d], D),
    Graffeo = graffeo:reaching_neighbours(DigG, [d]),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(
        normalize(graffeo:reaching_neighbours(MapG, [d])), normalize(Graffeo)
    ),
    cleanup(D).

%%% === M2-8: is_acyclic ===

is_acyclic_test() ->
    {MapGD, DigGD, DD} = build_fixture(dag_edges()),
    ?assertEqual(true, digraph_utils:is_acyclic(DD)),
    ?assertEqual(true, graffeo:is_acyclic(DigGD)),
    ?assertEqual(true, graffeo:is_acyclic(MapGD)),
    cleanup(DD),
    {MapGC, DigGC, DC} = build_fixture(cyclic_edges()),
    ?assertEqual(false, digraph_utils:is_acyclic(DC)),
    ?assertEqual(false, graffeo:is_acyclic(DigGC)),
    ?assertEqual(false, graffeo:is_acyclic(MapGC)),
    cleanup(DC).

%%% === M2-9: is_tree ===

is_tree_test() ->
    {MapG, DigG, D} = build_fixture(tree_edges()),
    ?assertEqual(digraph_utils:is_tree(D), graffeo:is_tree(DigG)),
    ?assertEqual(graffeo:is_tree(MapG), graffeo:is_tree(DigG)),
    cleanup(D),
    {MapG2, DigG2, D2} = build_fixture(cyclic_edges()),
    ?assertEqual(false, graffeo:is_tree(DigG2)),
    ?assertEqual(false, graffeo:is_tree(MapG2)),
    cleanup(D2).

%%% === M2-10: is_arborescence ===

is_arborescence_test() ->
    {MapG, DigG, D} = build_fixture(arb_edges()),
    ?assertEqual(digraph_utils:is_arborescence(D), graffeo:is_arborescence(DigG)),
    ?assertEqual(graffeo:is_arborescence(MapG), graffeo:is_arborescence(DigG)),
    cleanup(D),
    {_, DigG2, D2} = build_fixture(disconnected_edges()),
    ?assertEqual(false, graffeo:is_arborescence(DigG2)),
    cleanup(D2).

%%% === M2-11: arborescence_root ===

arborescence_root_test() ->
    {MapG, DigG, D} = build_fixture(arb_edges()),
    StdLib = digraph_utils:arborescence_root(D),
    Graffeo = graffeo:arborescence_root(DigG),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(graffeo:arborescence_root(MapG), Graffeo),
    cleanup(D),
    {_, DigG2, D2} = build_fixture(disconnected_edges()),
    ?assertEqual(no, graffeo:arborescence_root(DigG2)),
    cleanup(D2).

%%% === M2-12: loop_vertices ===

loop_vertices_test() ->
    {MapG, DigG, D} = build_fixture(loop_edges()),
    StdLib = digraph_utils:loop_vertices(D),
    Graffeo = graffeo:loop_vertices(DigG),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(normalize(graffeo:loop_vertices(MapG)), normalize(Graffeo)),
    cleanup(D),
    {_, DigG2, D2} = build_fixture(dag_edges()),
    ?assertEqual([], graffeo:loop_vertices(DigG2)),
    cleanup(D2).

%%% === M2-13: preorder ===

preorder_test() ->
    {MapG, DigG, D} = build_fixture(dag_edges()),
    StdLib = digraph_utils:preorder(D),
    Graffeo = graffeo:preorder(DigG),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(normalize(graffeo:preorder(MapG)), normalize(Graffeo)),
    cleanup(D).

%%% === M2-14: postorder ===

postorder_test() ->
    {MapG, DigG, D} = build_fixture(dag_edges()),
    StdLib = digraph_utils:postorder(D),
    Graffeo = graffeo:postorder(DigG),
    ?assertEqual(StdLib, Graffeo),
    ?assertEqual(normalize(graffeo:postorder(MapG)), normalize(Graffeo)),
    cleanup(D).

%%% === M2-PH: harness exists — verify normalize/1 ===

normalize_test() ->
    ?assertEqual([[1, 2], [3, 4]], normalize([[4, 3], [2, 1]])),
    ?assertEqual([a, b, c], normalize([c, a, b])).
