-module(graffeo_conn).
-moduledoc """
Connectivity algorithms over the read-half behaviour.

The DFS/forest engine is ported from the stdlib but runs over
`graffeo_backend` callbacks only — no direct stdlib calls.
""".

-export([
    topsort/3,
    preorder/3,
    postorder/3,
    dfs/3,
    components/3,
    strong_components/3,
    cyclic_strong_components/3,
    reachable/4,
    reachable_neighbours/4,
    reaching/4,
    reaching_neighbours/4,
    is_acyclic/3,
    loop_vertices/3,
    is_tree/3,
    is_arborescence/3,
    arborescence_root/3
]).

%%% === Public API ===

-doc "Topological sort; `{ok, Order}` or `false` if cyclic.".
-spec topsort(module(), term(), [graffeo:vertex()]) ->
    {ok, [graffeo:vertex()]} | false.
topsort(B, R, Vs) ->
    L = revpostorder(B, R, Vs),
    case length(forest_grouped(B, R, fun in_sf/4, L, first)) =:= length(Vs) of
        true -> {ok, L};
        false -> false
    end.

-doc "Vertices in DFS preorder.".
-spec preorder(module(), term(), [graffeo:vertex()]) -> [graffeo:vertex()].
preorder(B, R, Vs) ->
    Roots = roots(B, R, Vs),
    T = sets:new([{version, 2}]),
    {_, Acc} = ptraverse(Roots, fun out_sf/4, B, R, T, [], []),
    lists:reverse(lists:append(Acc)).

-doc "Vertices in DFS postorder.".
-spec postorder(module(), term(), [graffeo:vertex()]) -> [graffeo:vertex()].
postorder(B, R, Vs) ->
    Roots = roots(B, R, Vs),
    T = sets:new([{version, 2}]),
    {Acc, _} = posttraverse(Roots, B, R, T, []),
    lists:reverse(Acc).

-doc "DFS visit order (preorder).".
-spec dfs(module(), term(), [graffeo:vertex()]) -> [graffeo:vertex()].
dfs(B, R, Vs) ->
    preorder(B, R, Vs).

-doc "Connected components (undirected).".
-spec components(module(), term(), [graffeo:vertex()]) -> [[graffeo:vertex()]].
components(B, R, Vs) ->
    forest_grouped(B, R, fun inout_sf/4, Vs, first).

-doc "Strongly connected components (Kosaraju).".
-spec strong_components(module(), term(), [graffeo:vertex()]) -> [[graffeo:vertex()]].
strong_components(B, R, Vs) ->
    forest_grouped(B, R, fun in_sf/4, revpostorder(B, R, Vs), first).

-doc "Cyclic strongly connected components.".
-spec cyclic_strong_components(module(), term(), [graffeo:vertex()]) -> [[graffeo:vertex()]].
cyclic_strong_components(B, R, Vs) ->
    remove_singletons(strong_components(B, R, Vs), B, R, []).

-doc "Vertices reachable from `Vs` via outgoing edges (including `Vs`).".
-spec reachable(module(), term(), [graffeo:vertex()], [graffeo:vertex()]) -> [graffeo:vertex()].
reachable(B, R, _AllVs, Vs) ->
    lists:append(forest_grouped(B, R, fun out_sf/4, Vs, first)).

-doc "Vertices reachable from `Vs` (excluding `Vs` unless in a cycle).".
-spec reachable_neighbours(module(), term(), [graffeo:vertex()], [graffeo:vertex()]) ->
    [graffeo:vertex()].
reachable_neighbours(B, R, _AllVs, Vs) ->
    lists:append(forest_grouped(B, R, fun out_sf/4, Vs, not_first)).

-doc "Vertices from which `Vs` is reachable (including `Vs`).".
-spec reaching(module(), term(), [graffeo:vertex()], [graffeo:vertex()]) -> [graffeo:vertex()].
reaching(B, R, _AllVs, Vs) ->
    lists:append(forest_grouped(B, R, fun in_sf/4, Vs, first)).

-doc "Vertices from which `Vs` is reachable (excluding `Vs` unless in a cycle).".
-spec reaching_neighbours(module(), term(), [graffeo:vertex()], [graffeo:vertex()]) ->
    [graffeo:vertex()].
reaching_neighbours(B, R, _AllVs, Vs) ->
    lists:append(forest_grouped(B, R, fun in_sf/4, Vs, not_first)).

-doc "True if the graph is acyclic.".
-spec is_acyclic(module(), term(), [graffeo:vertex()]) -> boolean().
is_acyclic(B, R, Vs) ->
    case loop_vertices(B, R, Vs) of
        [] ->
            case topsort(B, R, Vs) of
                {ok, _} -> true;
                false -> false
            end;
        _ ->
            false
    end.

-doc "Vertices that have a self-loop.".
-spec loop_vertices(module(), term(), [graffeo:vertex()]) -> [graffeo:vertex()].
loop_vertices(B, R, Vs) ->
    [V || V <- Vs, lists:member(V, B:out_neighbours(R, V))].

-doc "True if the graph is a tree (undirected).".
-spec is_tree(module(), term(), [graffeo:vertex()]) -> boolean().
is_tree(B, R, Vs) ->
    B:no_edges(R) =:= B:no_vertices(R) - 1 andalso
        case components(B, R, Vs) of
            [_] -> true;
            _ -> false
        end.

-doc "True if the graph is an arborescence.".
-spec is_arborescence(module(), term(), [graffeo:vertex()]) -> boolean().
is_arborescence(B, R, Vs) ->
    arborescence_root(B, R, Vs) =/= no.

-doc "Returns `{yes, Root}` if arborescence, `no` otherwise.".
-spec arborescence_root(module(), term(), [graffeo:vertex()]) ->
    {yes, graffeo:vertex()} | no.
arborescence_root(B, R, Vs) ->
    case B:no_edges(R) =:= B:no_vertices(R) - 1 of
        true ->
            try
                F = fun(V, Z) ->
                    case B:in_degree(R, V) of
                        1 -> Z;
                        0 when Z =:= [] -> [V]
                    end
                end,
                [Root] = lists:foldl(F, [], Vs),
                {yes, Root}
            catch
                _:_ -> no
            end;
        false ->
            no
    end.

%%% === Internal: the forest engine ===

-type sf() :: fun((module(), term(), graffeo:vertex(), [graffeo:vertex()]) -> [graffeo:vertex()]).

-spec out_sf(module(), term(), graffeo:vertex(), [graffeo:vertex()]) -> [graffeo:vertex()].
out_sf(B, R, V, Vs) -> B:out_neighbours(R, V) ++ Vs.

-spec in_sf(module(), term(), graffeo:vertex(), [graffeo:vertex()]) -> [graffeo:vertex()].
in_sf(B, R, V, Vs) -> B:in_neighbours(R, V) ++ Vs.

-spec inout_sf(module(), term(), graffeo:vertex(), [graffeo:vertex()]) -> [graffeo:vertex()].
inout_sf(B, R, V, Vs) -> in_sf(B, R, V, out_sf(B, R, V, Vs)).

-spec forest_grouped(module(), term(), sf(), [graffeo:vertex()], first | not_first) ->
    [[graffeo:vertex()]].
forest_grouped(B, R, SF, Vs, HandleFirst) ->
    T = sets:new([{version, 2}]),
    F = fun(V, {T0, LL}) -> pretraverse_grouped(HandleFirst, V, SF, B, R, T0, LL) end,
    {_, LL} = lists:foldl(F, {T, []}, Vs),
    LL.

-spec pretraverse_grouped(
    first | not_first, graffeo:vertex(), sf(), module(), term(), sets:set(), [[graffeo:vertex()]]
) ->
    {sets:set(), [[graffeo:vertex()]]}.
pretraverse_grouped(first, V, SF, B, R, T, LL) ->
    ptraverse([V], SF, B, R, T, [], LL);
pretraverse_grouped(not_first, V, SF, B, R, T, LL) ->
    case sets:is_element(V, T) of
        false -> ptraverse(SF(B, R, V, []), SF, B, R, T, [], LL);
        true -> {T, LL}
    end.

-spec ptraverse([graffeo:vertex()], sf(), module(), term(), sets:set(), [graffeo:vertex()], [
    [graffeo:vertex()]
]) ->
    {sets:set(), [[graffeo:vertex()]]}.
ptraverse([V | Vs], SF, B, R, T0, Rs, LL) ->
    case sets:is_element(V, T0) of
        false ->
            T1 = sets:add_element(V, T0),
            ptraverse(SF(B, R, V, Vs), SF, B, R, T1, [V | Rs], LL);
        true ->
            ptraverse(Vs, SF, B, R, T0, Rs, LL)
    end;
ptraverse([], _SF, _B, _R, T, [], LL) ->
    {T, LL};
ptraverse([], _SF, _B, _R, T, Rs, LL) ->
    {T, [Rs | LL]}.

-spec revpostorder(module(), term(), [graffeo:vertex()]) -> [graffeo:vertex()].
revpostorder(B, R, Vs) ->
    T = sets:new([{version, 2}]),
    {L, _} = posttraverse(Vs, B, R, T, []),
    L.

-spec posttraverse([graffeo:vertex()], module(), term(), sets:set(), [graffeo:vertex()]) ->
    {[graffeo:vertex()], sets:set()}.
posttraverse([V | Vs], B, R, T0, Acc0) ->
    case sets:is_element(V, T0) of
        false ->
            T1 = sets:add_element(V, T0),
            {Acc1, T2} = posttraverse(B:out_neighbours(R, V), B, R, T1, Acc0),
            posttraverse(Vs, B, R, T2, [V | Acc1]);
        true ->
            posttraverse(Vs, B, R, T0, Acc0)
    end;
posttraverse([], _B, _R, T, Acc) ->
    {Acc, T}.

-spec roots(module(), term(), [graffeo:vertex()]) -> [graffeo:vertex()].
roots(B, R, Vs) ->
    R1 = [V || V <- Vs, B:in_degree(R, V) =:= 0],
    R2 = [X || [X | _] <- components(B, R, Vs)],
    R1 ++ R2.

-spec remove_singletons([[graffeo:vertex()]], module(), term(), [[graffeo:vertex()]]) ->
    [[graffeo:vertex()]].
remove_singletons([[V] = C | Cs], B, R, L) ->
    case lists:member(V, B:out_neighbours(R, V)) of
        true -> remove_singletons(Cs, B, R, [C | L]);
        false -> remove_singletons(Cs, B, R, L)
    end;
remove_singletons([C | Cs], B, R, L) ->
    remove_singletons(Cs, B, R, [C | L]);
remove_singletons([], _B, _R, L) ->
    L.
