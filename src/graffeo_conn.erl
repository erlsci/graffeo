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
    arborescence_root/3,
    subgraph/4, subgraph/5,
    condensation/4,
    filter_edges/4,
    contract/4, contract/5
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

%%% === Constructive algorithms ===

-doc """
Induced subgraph over the given vertices.

The result is a new graph of the same backend containing only the
vertices in `SubVs` and edges where both endpoints are in `SubVs`.
Labels and edge metadata are preserved.
""".
-spec subgraph(graffeo:graph(), module(), term(), [graffeo:vertex()]) -> graffeo:graph().
subgraph(G, B, R, SubVs) ->
    subgraph(G, B, R, SubVs, []).

-doc """
Induced subgraph with options.

Options: `{keep_labels, boolean()}` (default `true`),
`{type, inherit | [d_type()]}` (handle backend only; ignored for value).
Raises `badarg` on malformed options (faithful to `digraph_utils:subgraph/3`).
""".
-spec subgraph(
    graffeo:graph(),
    module(),
    term(),
    [graffeo:vertex()],
    [{keep_labels, boolean()} | {type, inherit | list()}]
) -> graffeo:graph().
subgraph(G, B, R, SubVs, Opts) ->
    {KeepLabels} = parse_subgraph_opts(Opts),
    subgraph_build(G, B, R, SubVs, KeepLabels).

-doc """
Condensation: one vertex per SCC, labelled with the member list.

The result is a new graph of the same backend. Each vertex is the
list of member vertices of a strongly connected component. An edge
exists between condensed vertices where any cross-component edge
exists in the original.
""".
-spec condensation(module(), term(), graffeo:graph(), [graffeo:vertex()]) -> graffeo:graph().
condensation(B, R, G, Vs) ->
    SCs = strong_components(B, R, Vs),
    V2SC = maps:from_list([{V, SC} || SC <- SCs, V <- SC]),
    Result0 = lists:foldl(
        fun(SC, Acc) ->
            B:build_add_vertex(Acc, SC, SC)
        end,
        B:empty_like(G),
        SCs
    ),
    SCPairs = lists:usort(
        lists:flatmap(
            fun(SC) ->
                [
                    {SC, maps:get(N, V2SC)}
                 || V <- SC,
                    N <- B:out_neighbours(R, V),
                    maps:get(N, V2SC) =/= SC
                ]
            end,
            SCs
        )
    ),
    lists:foldl(
        fun({FromSC, ToSC}, Acc) ->
            B:build_add_edge(Acc, FromSC, ToSC, #{})
        end,
        Result0,
        SCPairs
    ).

-doc """
Edge-induced subgraph by predicate.

Keeps edges where `Pred(From, To, Meta)` returns `true`, preserving
metadata. Only vertices incident to a kept edge appear in the result.
""".
-spec filter_edges(
    graffeo:graph(),
    module(),
    term(),
    fun((graffeo:vertex(), graffeo:vertex(), graffeo:edge_meta()) -> boolean())
) -> graffeo:graph().
filter_edges(G, B, R, Pred) ->
    Vs = B:vertices(R),
    lists:foldl(
        fun(From, GAcc) ->
            Ns = B:out_neighbours(R, From),
            lists:foldl(
                fun(To, GAcc2) ->
                    case B:edge_meta(R, From, To) of
                        {ok, Meta} ->
                            case Pred(From, To, Meta) of
                                true ->
                                    GAcc3 = ensure_build_vertex(B, GAcc2, From),
                                    GAcc4 = ensure_build_vertex(B, GAcc3, To),
                                    B:build_add_edge(GAcc4, From, To, Meta);
                                false ->
                                    GAcc2
                            end;
                        error ->
                            GAcc2
                    end
                end,
                GAcc,
                Ns
            )
        end,
        B:empty_like(G),
        Vs
    ).

-doc """
Quotient graph by class-function (default metadata on contracted edges).

Result vertices are the distinct `ClassFun(V)` values. For each edge
`(U, V)` where `ClassFun(U) =/= ClassFun(V)`, an edge is added between
the classes. Intra-class edges are dropped. Contracted edges carry
default metadata.
""".
-spec contract(
    graffeo:graph(),
    module(),
    term(),
    fun((graffeo:vertex()) -> term())
) -> graffeo:graph().
contract(G, B, R, ClassFun) ->
    contract(G, B, R, ClassFun, fun(_Old, New) -> New end).

-doc """
Quotient graph with a metadata merge function.

When multiple original edges collapse onto the same `(ClassA, ClassB)`,
their metadata is folded with `MergeFun(AccMeta, NextMeta)`.
""".
-spec contract(
    graffeo:graph(),
    module(),
    term(),
    fun((graffeo:vertex()) -> term()),
    fun((graffeo:edge_meta(), graffeo:edge_meta()) -> graffeo:edge_meta())
) -> graffeo:graph().
contract(G, B, R, ClassFun, MergeFun) ->
    Vs = B:vertices(R),
    Classes = lists:usort([ClassFun(V) || V <- Vs]),
    G0 = lists:foldl(
        fun(C, Acc) -> B:build_add_vertex(Acc, C) end,
        B:empty_like(G),
        Classes
    ),
    lists:foldl(
        fun(From, GAcc) ->
            ClassFrom = ClassFun(From),
            Ns = B:out_neighbours(R, From),
            lists:foldl(
                fun(To, GAcc2) ->
                    ClassTo = ClassFun(To),
                    case ClassFrom =:= ClassTo of
                        true ->
                            GAcc2;
                        false ->
                            Meta =
                                case B:edge_meta(R, From, To) of
                                    {ok, M} -> M;
                                    error -> #{}
                                end,
                            merge_contracted_edge(B, GAcc2, ClassFrom, ClassTo, Meta, MergeFun)
                    end
                end,
                GAcc,
                Ns
            )
        end,
        G0,
        Vs
    ).

-spec merge_contracted_edge(
    module(),
    graffeo:graph(),
    term(),
    term(),
    graffeo:edge_meta(),
    fun((graffeo:edge_meta(), graffeo:edge_meta()) -> graffeo:edge_meta())
) -> graffeo:graph().
merge_contracted_edge(B, G, ClassFrom, ClassTo, Meta, MergeFun) ->
    case B:edge_meta(graffeo:extract_ref(B, G), ClassFrom, ClassTo) of
        {ok, Existing} ->
            Merged = MergeFun(Existing, Meta),
            B:build_add_edge(G, ClassFrom, ClassTo, Merged);
        error ->
            B:build_add_edge(G, ClassFrom, ClassTo, Meta)
    end.

-spec ensure_build_vertex(module(), graffeo:graph(), graffeo:vertex()) -> graffeo:graph().
ensure_build_vertex(B, G, V) ->
    Ref = graffeo:extract_ref(B, G),
    case lists:member(V, B:vertices(Ref)) of
        true -> G;
        false -> B:build_add_vertex(G, V)
    end.

-spec subgraph_build(graffeo:graph(), module(), term(), [graffeo:vertex()], boolean()) ->
    graffeo:graph().
subgraph_build(G, B, R, SubVs, KeepLabels) ->
    SubSet = sets:from_list(SubVs, [{version, 2}]),
    Result0 = lists:foldl(
        fun(V, Acc) ->
            case B:vertex_label(R, V) of
                {ok, Label} when KeepLabels -> B:build_add_vertex(Acc, V, Label);
                {ok, _} -> B:build_add_vertex(Acc, V);
                error -> Acc
            end
        end,
        B:empty_like(G),
        SubVs
    ),
    lists:foldl(
        fun(V, Acc0) ->
            Ns = B:out_neighbours(R, V),
            lists:foldl(
                fun(N, Acc1) ->
                    case sets:is_element(N, SubSet) of
                        true when KeepLabels ->
                            Meta =
                                case B:edge_meta(R, V, N) of
                                    {ok, M} -> M;
                                    error -> #{}
                                end,
                            B:build_add_edge(Acc1, V, N, Meta);
                        true ->
                            B:build_add_edge(Acc1, V, N, #{});
                        false ->
                            Acc1
                    end
                end,
                Acc0,
                Ns
            )
        end,
        Result0,
        SubVs
    ).

-spec parse_subgraph_opts([{keep_labels, boolean()} | {type, inherit | list()}]) -> {boolean()}.
parse_subgraph_opts(Opts) ->
    parse_subgraph_opts(Opts, true).

-spec parse_subgraph_opts([{keep_labels, boolean()} | {type, inherit | list()}], boolean()) ->
    {boolean()}.
parse_subgraph_opts([], KeepLabels) ->
    {KeepLabels};
parse_subgraph_opts([{keep_labels, V} | Rest], _KL) when is_boolean(V) ->
    parse_subgraph_opts(Rest, V);
parse_subgraph_opts([{type, V} | Rest], KL) when V =:= inherit; is_list(V) ->
    parse_subgraph_opts(Rest, KL);
parse_subgraph_opts(_, _KL) ->
    erlang:error(badarg).

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
