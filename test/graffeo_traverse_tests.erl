-module(graffeo_traverse_tests).

-include_lib("eunit/include/eunit.hrl").

%% F-12: directional BFS with edge-type filter and distances
bfs_direction_filter_test() ->
    %% a → b → c, a → d
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b, #{weight => 1, label => road}),
    G2 = graffeo:add_edge(G1, b, c, #{weight => 1, label => road}),
    G3 = graffeo:add_edge(G2, a, d, #{weight => 1, label => rail}),
    %% out BFS from a, no filter
    OutAll = graffeo:bfs(G3, a),
    ?assertEqual(4, length(OutAll)),
    ?assertEqual({a, 0}, lists:keyfind(a, 1, OutAll)),
    ?assertEqual({b, 1}, lists:keyfind(b, 1, OutAll)),
    ?assertEqual({c, 2}, lists:keyfind(c, 1, OutAll)),
    ?assertEqual({d, 1}, lists:keyfind(d, 1, OutAll)),
    %% in BFS from c
    InFromC = graffeo:bfs(G3, c, #{direction => in}),
    InVerts = [V || {V, _} <- InFromC],
    ?assert(lists:member(b, InVerts)),
    ?assert(lists:member(a, InVerts)),
    %% both direction from b
    BothFromB = graffeo:bfs(G3, b, #{direction => both}),
    BothVerts = [V || {V, _} <- BothFromB],
    ?assert(lists:member(a, BothVerts)),
    ?assert(lists:member(c, BothVerts)),
    %% filter: only "road" edges (need edge_meta to check)
    %% For now we filter by destination: only go to b or c
    FilterFun = fun(_From, To) -> lists:member(To, [b, c]) end,
    Filtered = graffeo:bfs(G3, a, #{filter => FilterFun}),
    FilteredVerts = [V || {V, _} <- Filtered],
    ?assert(lists:member(b, FilteredVerts)),
    ?assert(lists:member(c, FilteredVerts)),
    ?assertNot(lists:member(d, FilteredVerts)).

%% F-13: degree metrics
degree_centrality_test() ->
    %%   a → b, a → c, b → c
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, a, c),
    G3 = graffeo:add_edge(G2, b, c),
    %% in/out degree via facade
    ?assertEqual(0, graffeo:in_degree(G3, a)),
    ?assertEqual(2, graffeo:out_degree(G3, a)),
    ?assertEqual(1, graffeo:in_degree(G3, b)),
    ?assertEqual(1, graffeo:out_degree(G3, b)),
    ?assertEqual(2, graffeo:in_degree(G3, c)),
    ?assertEqual(0, graffeo:out_degree(G3, c)),
    %% total degree
    ?assertEqual(2, graffeo:degree(G3, a)),
    ?assertEqual(2, graffeo:degree(G3, b)),
    ?assertEqual(2, graffeo:degree(G3, c)),
    %% normalised degree centrality: degree / (2*(N-1)), N=3
    ?assert(abs(graffeo:degree_centrality(G3, a) - 0.5) < 0.001),
    ?assert(abs(graffeo:degree_centrality(G3, b) - 0.5) < 0.001),
    %% top-k
    TopK = graffeo:top_k_by_degree(G3, 2),
    ?assertEqual(2, length(TopK)),
    [_, _] = TopK.

%% F-14: reverse traversal first-class (direction => in)
reverse_traversal_test() ->
    %%   a → b → c → d
    G0 = graffeo:new(),
    G1 = graffeo:add_edge(G0, a, b),
    G2 = graffeo:add_edge(G1, b, c),
    G3 = graffeo:add_edge(G2, c, d),
    %% reverse BFS from d should find c, b, a with increasing distance
    Deps = graffeo:bfs(G3, d, #{direction => in}),
    ?assertEqual({d, 0}, lists:keyfind(d, 1, Deps)),
    ?assertEqual({c, 1}, lists:keyfind(c, 1, Deps)),
    ?assertEqual({b, 2}, lists:keyfind(b, 1, Deps)),
    ?assertEqual({a, 3}, lists:keyfind(a, 1, Deps)).
