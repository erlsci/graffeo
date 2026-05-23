-module(graffeo_path).
-moduledoc """
Path and shortest-path algorithms over the read-half behaviour.
""".

-export([
    dijkstra/3,
    dijkstra/4,
    get_path/4,
    get_cycle/3,
    get_short_path/4,
    get_short_cycle/3
]).

-type cost_fun() :: fun((graffeo:edge_meta()) -> number()).
-type dist_map() :: #{graffeo:vertex() => number()}.
-type prev_map() :: #{graffeo:vertex() => graffeo:vertex()}.

-export_type([dist_map/0, prev_map/0]).

%%% === Dijkstra ===

-doc "Dijkstra with the stored edge weight as cost.".
-spec dijkstra(module(), term(), graffeo:vertex()) ->
    {dist_map(), prev_map()}.
dijkstra(Backend, Ref, Source) ->
    dijkstra(Backend, Ref, Source, #{}).

-doc """
Dijkstra with options. Supported options:
- `cost`: a `fun(edge_meta()) -> number()` for custom costs.

**Precondition:** costs must be non-negative. Negative costs yield
undefined results; use Bellman-Ford for negative-weight graphs (later band).
""".
-spec dijkstra(module(), term(), graffeo:vertex(), map()) ->
    {dist_map(), prev_map()}.
dijkstra(Backend, Ref, Source, Opts) ->
    CostFun = maps:get(cost, Opts, fun default_cost/1),
    Dist0 = #{Source => 0},
    Prev0 = #{},
    Queue0 = gb_sets:singleton({0, Source}),
    dijkstra_loop(Backend, Ref, CostFun, Queue0, Dist0, Prev0).

%%% === Path/cycle queries ===

-doc "DFS path from `V1` to `V2`, or `false`.".
-spec get_path(module(), term(), graffeo:vertex(), graffeo:vertex()) ->
    [graffeo:vertex()] | false.
get_path(B, R, V1, V2) ->
    one_path(B:out_neighbours(R, V1), V2, [], [V1], [V1], 1, B, R, 1).

-doc "A cycle through `V` (DFS), or `false`.".
-spec get_cycle(module(), term(), graffeo:vertex()) ->
    [graffeo:vertex()] | false.
get_cycle(B, R, V) ->
    case one_path(B:out_neighbours(R, V), V, [], [V], [V], 2, B, R, 1) of
        false ->
            case lists:member(V, B:out_neighbours(R, V)) of
                true -> [V];
                false -> false
            end;
        Vs ->
            Vs
    end.

-doc """
Shortest (fewest-edges) path from `V1` to `V2` (BFS), or `false`.

When `V1 =:= V2`, returns the shortest cycle through `V`.
""".
-spec get_short_path(module(), term(), graffeo:vertex(), graffeo:vertex()) ->
    [graffeo:vertex()] | false.
get_short_path(B, R, V1, V2) ->
    Visited = #{V1 => start},
    Q = queue:new(),
    Q1 = enqueue_neighbours(B, R, V1, Q),
    spath(Q1, B, R, V2, Visited).

-doc "Shortest cycle through `V`, or `false`.".
-spec get_short_cycle(module(), term(), graffeo:vertex()) ->
    [graffeo:vertex()] | false.
get_short_cycle(B, R, V) ->
    get_short_path(B, R, V, V).

%%% --- Internal: Dijkstra ---

-spec dijkstra_loop(module(), term(), cost_fun(), gb_sets:set(), dist_map(), prev_map()) ->
    {dist_map(), prev_map()}.
dijkstra_loop(Backend, Ref, CostFun, Queue, Dist, Prev) ->
    case gb_sets:is_empty(Queue) of
        true ->
            {Dist, Prev};
        false ->
            {{UDist, U}, Queue1} = gb_sets:take_smallest(Queue),
            case maps:get(U, Dist, infinity) of
                D when D < UDist ->
                    dijkstra_loop(Backend, Ref, CostFun, Queue1, Dist, Prev);
                _ ->
                    Neighbours = Backend:out_neighbours(Ref, U),
                    {Queue2, Dist2, Prev2} = lists:foldl(
                        fun(V, {Q, D, P}) ->
                            Meta = Backend:edge_meta(Ref, U, V),
                            Cost = edge_cost(CostFun, Meta),
                            Alt = UDist + Cost,
                            case Alt < maps:get(V, D, infinity) of
                                true ->
                                    {gb_sets:add_element({Alt, V}, Q), D#{V => Alt}, P#{V => U}};
                                false ->
                                    {Q, D, P}
                            end
                        end,
                        {Queue1, Dist, Prev},
                        Neighbours
                    ),
                    dijkstra_loop(Backend, Ref, CostFun, Queue2, Dist2, Prev2)
            end
    end.

-spec edge_cost(cost_fun(), {ok, graffeo:edge_meta()} | error) -> number().
edge_cost(CostFun, {ok, Meta}) ->
    CostFun(Meta);
edge_cost(_CostFun, error) ->
    1.

-spec default_cost(graffeo:edge_meta()) -> number().
default_cost(#{weight := W}) -> W;
default_cost(_) -> 1.

%%% --- Internal: DFS path (one_path, mirrors digraph) ---

-spec one_path(
    [graffeo:vertex()],
    graffeo:vertex(),
    [{[graffeo:vertex()], [graffeo:vertex()]}],
    [graffeo:vertex()],
    [graffeo:vertex()],
    pos_integer(),
    module(),
    term(),
    non_neg_integer()
) -> [graffeo:vertex()] | false.
one_path([W | Ws], W, Cont, Xs, Ps, Prune, B, R, Counter) ->
    case prune_short_path(Counter, Prune) of
        short -> one_path(Ws, W, Cont, Xs, Ps, Prune, B, R, Counter);
        ok -> lists:reverse([W | Ps])
    end;
one_path([V | Vs], W, Cont, Xs, Ps, Prune, B, R, Counter) ->
    case lists:member(V, Xs) of
        true ->
            one_path(Vs, W, Cont, Xs, Ps, Prune, B, R, Counter);
        false ->
            one_path(
                B:out_neighbours(R, V),
                W,
                [{Vs, Ps} | Cont],
                [V | Xs],
                [V | Ps],
                Prune,
                B,
                R,
                Counter + 1
            )
    end;
one_path([], W, [{Vs, Ps} | Cont], Xs, _, Prune, B, R, Counter) ->
    one_path(Vs, W, Cont, Xs, Ps, Prune, B, R, Counter - 1);
one_path([], _, [], _, _, _, _B, _R, _Counter) ->
    false.

-spec prune_short_path(non_neg_integer(), pos_integer()) -> short | ok.
prune_short_path(Counter, Min) when Counter < Min -> short;
prune_short_path(_, _) -> ok.

%%% --- Internal: BFS short path ---

-spec spath(
    queue:queue({graffeo:vertex(), graffeo:vertex()}), module(), term(), graffeo:vertex(), map()
) ->
    [graffeo:vertex()] | false.
spath(Q, B, R, Sink, Visited) ->
    case queue:out(Q) of
        {{value, {From, V2}}, Q1} ->
            case V2 =:= Sink of
                true ->
                    follow_path(From, Visited, [V2]);
                false ->
                    case maps:is_key(V2, Visited) of
                        true ->
                            spath(Q1, B, R, Sink, Visited);
                        false ->
                            Visited1 = Visited#{V2 => From},
                            Q2 = enqueue_neighbours(B, R, V2, Q1),
                            spath(Q2, B, R, Sink, Visited1)
                    end
            end;
        {empty, _} ->
            false
    end.

-spec follow_path(graffeo:vertex(), map(), [graffeo:vertex()]) -> [graffeo:vertex()].
follow_path(V, Visited, Path) ->
    case maps:get(V, Visited) of
        start -> [V | Path];
        Prev -> follow_path(Prev, Visited, [V | Path])
    end.

-spec enqueue_neighbours(module(), term(), graffeo:vertex(), queue:queue()) -> queue:queue().
enqueue_neighbours(B, R, V, Q) ->
    lists:foldl(
        fun(N, Acc) -> queue:in({V, N}, Acc) end,
        Q,
        B:out_neighbours(R, V)
    ).
