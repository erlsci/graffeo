-module(graffeo_conn_tests).

-include_lib("eunit/include/eunit.hrl").

%% F-9: topsort correct on a DAG
topsort_dag_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    G3 = graffeo:add_edge(G2, a, c),
    {ok, Order} = graffeo:topsort(G3),
    ?assertEqual(3, length(Order)),
    PosA = pos(a, Order),
    PosB = pos(b, Order),
    PosC = pos(c, Order),
    ?assert(PosA < PosB),
    ?assert(PosB < PosC).

%% F-9: topsort returns false on a cycle
topsort_cycle_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    G3 = graffeo:add_edge(G2, c, a),
    ?assertEqual(false, graffeo:topsort(G3)).

%% topsort on a single vertex
topsort_single_test() ->
    G = graffeo:add_vertex(graffeo:new(), x),
    ?assertEqual({ok, [x]}, graffeo:topsort(G)).

%% topsort on empty graph
topsort_empty_test() ->
    G = graffeo:new(),
    ?assertEqual({ok, []}, graffeo:topsort(G)).

%% topsort on a diamond DAG
topsort_diamond_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, a, c),
    G3 = graffeo:add_edge(G2, b, d),
    G4 = graffeo:add_edge(G3, c, d),
    {ok, Order} = graffeo:topsort(G4),
    ?assert(pos(a, Order) < pos(b, Order)),
    ?assert(pos(a, Order) < pos(c, Order)),
    ?assert(pos(b, Order) < pos(d, Order)),
    ?assert(pos(c, Order) < pos(d, Order)).

%% topsort on digraph backend
topsort_digraph_test() ->
    D = digraph:new(),
    digraph:add_vertex(D, a),
    digraph:add_vertex(D, b),
    digraph:add_vertex(D, c),
    digraph:add_edge(D, a, b),
    digraph:add_edge(D, b, c),
    G = graffeo_digraph:wrap(D),
    {ok, Order} = graffeo:topsort(G),
    ?assert(pos(a, Order) < pos(b, Order)),
    ?assert(pos(b, Order) < pos(c, Order)),
    digraph:delete(D).

%% F-8: DFS engine contains no digraph: calls anywhere in the source
no_digraph_calls_in_engine_test() ->
    {ok, Bin} = file:read_file("src/graffeo_conn.erl"),
    ?assertEqual(nomatch, binary:match(Bin, <<"digraph:">>)).

is_acyclic_with_selfloop_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, a),
    G2 = graffeo:add_edge(G1, a, b),
    ?assertEqual(false, graffeo:is_acyclic(G2)).

cyclic_strong_components_selfloop_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, a),
    G2 = graffeo:add_edge(G1, a, b),
    CSCs = graffeo:cyclic_strong_components(G2),
    ?assertEqual([[a]], CSCs).

reachable_neighbours_overlap_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    R = graffeo:reachable_neighbours(G2, [a, b]),
    ?assert(lists:member(b, R)),
    ?assert(lists:member(c, R)).

reaching_neighbours_overlap_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    R = graffeo:reaching_neighbours(G2, [b, c]),
    ?assert(lists:member(a, R)),
    ?assert(lists:member(b, R)).

arborescence_root_non_tree_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, a, c),
    G3 = graffeo:add_edge(G2, b, c),
    ?assertEqual(no, graffeo:arborescence_root(G3)).

subgraph_with_type_opt_test() ->
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    Sub = graffeo:subgraph(G2, [a, b], [{type, inherit}]),
    ?assertEqual(lists:sort([a, b]), lists:sort(graffeo:vertices(Sub))).

%%% --- helpers ---

pos(X, List) ->
    pos(X, List, 1).
pos(X, [X | _], N) ->
    N;
pos(X, [_ | T], N) ->
    pos(X, T, N + 1).
