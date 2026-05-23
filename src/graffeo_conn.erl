-module(graffeo_conn).
-moduledoc """
Connectivity algorithms over the read-half behaviour.

The DFS/postorder engine is ported from the stdlib but runs
over `graffeo_backend` callbacks only — no direct stdlib calls.
""".

-export([
    topsort/3,
    postorder/3,
    dfs/3
]).

-doc """
Topological sort of the graph. Returns `{ok, Vertices}` in
topological order, or `false` if the graph contains a cycle.
""".
-spec topsort(module(), term(), [graffeo:vertex()]) ->
    {ok, [graffeo:vertex()]} | false.
topsort(Backend, Ref, Vertices) ->
    Order = lists:reverse(postorder(Backend, Ref, Vertices)),
    case is_topsort(Backend, Ref, Order) of
        true -> {ok, Order};
        false -> false
    end.

-doc "Vertices in reverse postorder (topological when acyclic).".
-spec postorder(module(), term(), [graffeo:vertex()]) -> [graffeo:vertex()].
postorder(Backend, Ref, Vertices) ->
    {_Visited, Acc} = forest(Backend, Ref, Vertices, sets:new([{version, 2}])),
    Acc.

-doc "Depth-first search; returns vertices in DFS visit order.".
-spec dfs(module(), term(), [graffeo:vertex()]) -> [graffeo:vertex()].
dfs(Backend, Ref, Vertices) ->
    {_Visited, Acc} = dfs_forest(Backend, Ref, Vertices, sets:new([{version, 2}])),
    Acc.

%%% --- Internal: the DFS/postorder engine ---

-spec forest(module(), term(), [graffeo:vertex()], sets:set()) ->
    {sets:set(), [graffeo:vertex()]}.
forest(Backend, Ref, Vertices, Visited0) ->
    lists:foldl(
        fun(V, {Vis, Acc}) ->
            case sets:is_element(V, Vis) of
                true ->
                    {Vis, Acc};
                false ->
                    {Vis1, Acc1} = post_traverse(Backend, Ref, V, Vis),
                    {Vis1, Acc ++ Acc1}
            end
        end,
        {Visited0, []},
        Vertices
    ).

-spec post_traverse(module(), term(), graffeo:vertex(), sets:set()) ->
    {sets:set(), [graffeo:vertex()]}.
post_traverse(Backend, Ref, V, Visited0) ->
    Visited1 = sets:add_element(V, Visited0),
    Neighbours = Backend:out_neighbours(Ref, V),
    {Visited2, ChildAcc} = lists:foldl(
        fun(N, {Vis, A}) ->
            case sets:is_element(N, Vis) of
                true ->
                    {Vis, A};
                false ->
                    {Vis1, A1} = post_traverse(Backend, Ref, N, Vis),
                    {Vis1, A ++ A1}
            end
        end,
        {Visited1, []},
        Neighbours
    ),
    {Visited2, ChildAcc ++ [V]}.

-spec dfs_forest(module(), term(), [graffeo:vertex()], sets:set()) ->
    {sets:set(), [graffeo:vertex()]}.
dfs_forest(Backend, Ref, Vertices, Visited0) ->
    lists:foldl(
        fun(V, {Vis, Acc}) ->
            case sets:is_element(V, Vis) of
                true ->
                    {Vis, Acc};
                false ->
                    {Vis1, Acc1} = pre_traverse(Backend, Ref, V, Vis),
                    {Vis1, Acc ++ Acc1}
            end
        end,
        {Visited0, []},
        Vertices
    ).

-spec pre_traverse(module(), term(), graffeo:vertex(), sets:set()) ->
    {sets:set(), [graffeo:vertex()]}.
pre_traverse(Backend, Ref, V, Visited0) ->
    Visited1 = sets:add_element(V, Visited0),
    Neighbours = Backend:out_neighbours(Ref, V),
    {Visited2, Acc} = lists:foldl(
        fun(N, {Vis, A}) ->
            case sets:is_element(N, Vis) of
                true -> {Vis, A};
                false -> pre_traverse(Backend, Ref, N, Vis)
            end
        end,
        {Visited1, []},
        Neighbours
    ),
    {Visited2, [V | Acc]}.

%% Verify a candidate topological order: for every edge u→v,
%% u appears before v in the order.
-spec is_topsort(module(), term(), [graffeo:vertex()]) -> boolean().
is_topsort(Backend, Ref, Order) ->
    Vertices = Backend:vertices(Ref),
    case length(Order) =:= length(Vertices) of
        false ->
            false;
        true ->
            check_order(Backend, Ref, Order, Vertices)
    end.

-spec check_order(module(), term(), [graffeo:vertex()], [graffeo:vertex()]) -> boolean().
check_order(Backend, Ref, Order, Vertices) ->
    Pos = maps:from_list(lists:zip(Order, lists:seq(1, length(Order)))),
    lists:all(
        fun(V) ->
            Ns = Backend:out_neighbours(Ref, V),
            VPos = maps:get(V, Pos),
            lists:all(fun(N) -> maps:get(N, Pos) > VPos end, Ns)
        end,
        Vertices
    ).
