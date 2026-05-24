-module(graffeo_primitives_tests).
-moduledoc false.

-include_lib("eunit/include/eunit.hrl").

%%% === filter_edges/2 ===

filter_edges_map_basic_test() ->
    G = build_labelled_map(),
    R = graffeo:filter_edges(G, fun(_F, _T, #{label := L}) -> L =:= red end),
    ?assertEqual(lists:sort([a, b, c]), lists:sort(graffeo:vertices(R))),
    ?assertEqual(2, graffeo:no_edges(R)),
    ?assertEqual({ok, #{label => red}}, graffeo:edge_meta(R, a, b)),
    ?assertEqual({ok, #{label => red}}, graffeo:edge_meta(R, a, c)),
    ?assertEqual(error, graffeo:edge_meta(R, b, c)).

filter_edges_digraph_basic_test() ->
    G = build_labelled_digraph(),
    R = graffeo:filter_edges(G, fun(_F, _T, #{label := L}) -> L =:= red end),
    ?assertEqual(lists:sort([a, b, c]), lists:sort(graffeo:vertices(R))),
    ?assertEqual(2, graffeo:no_edges(R)),
    ?assertEqual({ok, #{label => red}}, graffeo:edge_meta(R, a, b)),
    graffeo_ets:delete(R),
    graffeo_ets:delete(G).

filter_edges_always_false_test() ->
    G = build_labelled_map(),
    R = graffeo:filter_edges(G, fun(_, _, _) -> false end),
    ?assertEqual(0, graffeo:no_vertices(R)),
    ?assertEqual(0, graffeo:no_edges(R)).

filter_edges_always_true_test() ->
    G = build_labelled_map(),
    R = graffeo:filter_edges(G, fun(_, _, _) -> true end),
    ?assertEqual(3, graffeo:no_vertices(R)),
    ?assertEqual(3, graffeo:no_edges(R)),
    ?assertEqual({ok, #{label => red}}, graffeo:edge_meta(R, a, b)),
    ?assertEqual({ok, #{label => blue}}, graffeo:edge_meta(R, b, c)).

filter_edges_preserves_metadata_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, x, y, #{weight => 42, label => data}),
    R = graffeo:filter_edges(G1, fun(_, _, _) -> true end),
    ?assertEqual({ok, #{weight => 42, label => data}}, graffeo:edge_meta(R, x, y)).

filter_edges_cross_tier_parity_test() ->
    MapG = build_labelled_map(),
    DigG = build_labelled_digraph(),
    Pred = fun(_F, _T, #{label := L}) -> L =:= red end,
    MapR = graffeo:filter_edges(MapG, Pred),
    DigR = graffeo:filter_edges(DigG, Pred),
    ?assertEqual(
        lists:sort(graffeo:vertices(MapR)),
        lists:sort(graffeo:vertices(DigR))
    ),
    ?assertEqual(graffeo:no_edges(MapR), graffeo:no_edges(DigR)),
    graffeo_ets:delete(DigR),
    graffeo_ets:delete(DigG).

filter_edges_isolated_vertex_excluded_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_vertex(G0, isolated),
    G2 = graffeo:add_edge(G1, a, b),
    R = graffeo:filter_edges(G2, fun(_, _, _) -> true end),
    ?assertNot(lists:member(isolated, graffeo:vertices(R))),
    ?assertEqual(2, graffeo:no_vertices(R)).

%%% === bfs arity-3 filter ===

bfs_arity2_backward_compat_test() ->
    G = build_labelled_map(),
    R = graffeo:bfs(G, a, #{filter => fun(_F, _T) -> true end}),
    ?assertEqual(3, length(R)).

bfs_arity3_metadata_filter_test() ->
    G = build_labelled_map(),
    %% red filter: a→b (red) and a→c (red) both match; b→c (blue) does not
    R = graffeo:bfs(G, a, #{filter => fun(_F, _T, #{label := L}) -> L =:= red end}),
    Vs = [V || {V, _} <- R],
    ?assert(lists:member(a, Vs)),
    ?assert(lists:member(b, Vs)),
    ?assert(lists:member(c, Vs)),
    %% blue filter: only b→c is blue; from a, no blue edges so only a is reached
    R2 = graffeo:bfs(G, a, #{filter => fun(_F, _T, #{label := L}) -> L =:= blue end}),
    ?assertEqual([{a, 0}], R2).

bfs_arity3_digraph_test() ->
    G = build_labelled_digraph(),
    R = graffeo:bfs(G, a, #{filter => fun(_F, _T, #{label := L}) -> L =:= red end}),
    Vs = [V || {V, _} <- R],
    ?assert(lists:member(a, Vs)),
    ?assert(lists:member(b, Vs)),
    graffeo_ets:delete(G).

%%% === contract/2,3 ===

contract_map_basic_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, {s1, a}, {s1, b}),
    G2 = graffeo:add_edge(G1, {s2, a}, {s2, c}),
    G3 = graffeo:add_edge(G2, {s1, a}, {s1, a}),
    C = graffeo:contract(G3, fun({_S, Slug}) -> Slug end),
    ?assertEqual(lists:sort([a, b, c]), lists:sort(graffeo:vertices(C))),
    ?assertEqual(2, graffeo:no_edges(C)).

contract_digraph_basic_test() ->
    G = graffeo_ets:new(),
    ok = graffeo_ets:add_edge(G, {s1, a}, {s1, b}),
    ok = graffeo_ets:add_edge(G, {s2, a}, {s2, c}),
    C = graffeo:contract(G, fun({_S, Slug}) -> Slug end),
    ?assertEqual(lists:sort([a, b, c]), lists:sort(graffeo:vertices(C))),
    ?assertEqual(2, graffeo:no_edges(C)),
    graffeo_ets:delete(C),
    graffeo_ets:delete(G).

contract_drops_intraclass_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, {s1, a}, {s1, b}),
    G2 = graffeo:add_edge(G1, {s1, b}, {s1, a}),
    C = graffeo:contract(G2, fun({_S, Slug}) -> Slug end),
    ?assertEqual(2, graffeo:no_edges(C)).

contract_merge_fun_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, {s1, a}, {s1, b}, #{label => #{types => [related]}}),
    G2 = graffeo:add_edge(G1, {s2, a}, {s2, b}, #{label => #{types => [prereq]}}),
    MergeFun = fun(#{label := #{types := T1}}, #{label := #{types := T2}}) ->
        #{label => #{types => lists:usort(T1 ++ T2)}}
    end,
    C = graffeo:contract(G2, fun({_S, Slug}) -> Slug end, MergeFun),
    {ok, #{label := #{types := Types}}} = graffeo:edge_meta(C, a, b),
    ?assertEqual([prereq, related], Types).

contract_identity_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    C = graffeo:contract(G2, fun(V) -> V end),
    ?assertEqual(
        lists:sort(graffeo:vertices(G2)),
        lists:sort(graffeo:vertices(C))
    ),
    ?assertEqual(graffeo:no_edges(G2), graffeo:no_edges(C)).

contract_identity_drops_selfloops_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, a),
    G2 = graffeo:add_edge(G1, a, b),
    C = graffeo:contract(G2, fun(V) -> V end),
    ?assertEqual(1, graffeo:no_edges(C)),
    ?assertEqual(error, graffeo:edge_meta(C, a, a)).

contract_cross_tier_parity_test() ->
    MapG = graffeo:new(),
    G1 = graffeo:add_edge(MapG, {s1, a}, {s1, b}, #{label => x}),
    G2 = graffeo:add_edge(G1, {s2, a}, {s2, c}, #{label => y}),
    DigG = graffeo_ets:new(),
    ok = graffeo_ets:add_edge(DigG, {s1, a}, {s1, b}, #{label => x}),
    ok = graffeo_ets:add_edge(DigG, {s2, a}, {s2, c}, #{label => y}),
    ClassFun = fun({_S, Slug}) -> Slug end,
    MapC = graffeo:contract(G2, ClassFun),
    DigC = graffeo:contract(DigG, ClassFun),
    ?assertEqual(
        lists:sort(graffeo:vertices(MapC)),
        lists:sort(graffeo:vertices(DigC))
    ),
    ?assertEqual(graffeo:no_edges(MapC), graffeo:no_edges(DigC)),
    graffeo_ets:delete(DigC),
    graffeo_ets:delete(DigG).

contract_by_scc_isomorphic_to_condensation_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, a),
    G3 = graffeo:add_edge(G2, b, c),
    G4 = graffeo:add_edge(G3, c, d),
    G5 = graffeo:add_edge(G4, d, c),
    Cond = graffeo:condensation(G5),
    SCCs = graffeo:strong_components(G5),
    V2SCC = maps:from_list([{V, lists:sort(SC)} || SC <- SCCs, V <- SC]),
    Contracted = graffeo:contract(G5, fun(V) -> maps:get(V, V2SCC) end),
    CondVs = lists:sort([lists:sort(V) || V <- graffeo:vertices(Cond)]),
    ContrVs = lists:sort(graffeo:vertices(Contracted)),
    ?assertEqual(CondVs, ContrVs),
    ?assertEqual(graffeo:no_edges(Cond), graffeo:no_edges(Contracted)).

%%% === Helpers ===

build_labelled_map() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b, #{label => red}),
    G2 = graffeo:add_edge(G1, b, c, #{label => blue}),
    graffeo:add_edge(G2, a, c, #{label => red}).

build_labelled_digraph() ->
    G = graffeo_ets:new(),
    ok = graffeo_ets:add_edge(G, a, b, #{label => red}),
    ok = graffeo_ets:add_edge(G, b, c, #{label => blue}),
    ok = graffeo_ets:add_edge(G, a, c, #{label => red}),
    G.
