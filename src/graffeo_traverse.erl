-module(graffeo_traverse).
-moduledoc """
Traversal and degree-metric algorithms over the read-half behaviour.

BFS supports direction (`out`/`in`/`both`) and an optional edge-type
filter predicate, yielding vertices with distances. Degree metrics
cover in/out/total degree, normalised degree centrality, and top-k.
""".

-export([
    bfs/4,
    in_degree/3,
    out_degree/3,
    degree/3,
    degree_centrality/3,
    top_k_by_degree/4
]).

-doc "BFS traversal direction: outgoing, incoming, or both.".
-type direction() :: out | in | both.
-type filter() ::
    fun((graffeo:vertex(), graffeo:vertex()) -> boolean())
    | fun((graffeo:vertex(), graffeo:vertex(), graffeo:edge_meta()) -> boolean()).
-doc "BFS result: vertices paired with their distance from the source.".
-type bfs_result() :: [{graffeo:vertex(), non_neg_integer()}].

-export_type([direction/0, bfs_result/0]).

-doc """
Breadth-first search from `Source` in the given direction, with an
optional filter. Returns `[{Vertex, Distance}]`.

Options:
- `direction`: `out` (default), `in`, or `both`.
- `filter`: `fun(From, To) -> boolean()` or
  `fun(From, To, Meta) -> boolean()` — only traverse edges where
  the filter returns `true`. The arity-3 form receives the edge
  metadata from `edge_meta/3`.
""".
-spec bfs(module(), term(), graffeo:vertex(), map()) -> bfs_result().
bfs(Backend, Ref, Source, Opts) ->
    Dir = maps:get(direction, Opts, out),
    RawFilter = maps:get(filter, Opts, fun(_From, _To) -> true end),
    Filter = normalise_filter(RawFilter, Backend, Ref),
    bfs_loop(
        Backend, Ref, Dir, Filter, [{Source, 0}], sets:from_list([Source], [{version, 2}]), []
    ).

%%% --- Degree metrics ---

-doc "In-degree of vertex `V`.".
-spec in_degree(module(), term(), graffeo:vertex()) -> non_neg_integer().
in_degree(Backend, Ref, V) ->
    Backend:in_degree(Ref, V).

-doc "Out-degree of vertex `V`.".
-spec out_degree(module(), term(), graffeo:vertex()) -> non_neg_integer().
out_degree(Backend, Ref, V) ->
    Backend:out_degree(Ref, V).

-doc "Total degree (in + out) of vertex `V`.".
-spec degree(module(), term(), graffeo:vertex()) -> non_neg_integer().
degree(Backend, Ref, V) ->
    Backend:in_degree(Ref, V) + Backend:out_degree(Ref, V).

-doc """
Normalised degree centrality for vertex `V`:
`degree(V) / (2 * (N - 1))` where N is the vertex count.
Returns `0.0` for a single-vertex graph.
""".
-spec degree_centrality(module(), term(), graffeo:vertex()) -> float().
degree_centrality(Backend, Ref, V) ->
    N = Backend:no_vertices(Ref),
    case N of
        N when N =< 1 -> 0.0;
        _ -> degree(Backend, Ref, V) / (2 * (N - 1))
    end.

-doc """
Top-k vertices by total degree, descending.
Returns `[{Vertex, Degree}]`.
""".
-spec top_k_by_degree(module(), term(), [graffeo:vertex()], pos_integer()) ->
    [{graffeo:vertex(), non_neg_integer()}].
top_k_by_degree(Backend, Ref, Vertices, K) ->
    Scored = [{V, degree(Backend, Ref, V)} || V <- Vertices],
    Sorted = lists:sort(fun({_, D1}, {_, D2}) -> D1 > D2 end, Scored),
    lists:sublist(Sorted, K).

%%% --- Filter normalisation ---

-spec normalise_filter(filter(), module(), term()) ->
    fun((graffeo:vertex(), graffeo:vertex()) -> boolean()).
normalise_filter(F, Backend, Ref) ->
    case erlang:fun_info(F, arity) of
        {arity, 2} ->
            F;
        {arity, 3} ->
            fun(From, To) ->
                case Backend:edge_meta(Ref, From, To) of
                    {ok, Meta} -> F(From, To, Meta);
                    error -> false
                end
            end
    end.

%%% --- Internal BFS ---

-spec bfs_loop(
    module(),
    term(),
    direction(),
    filter(),
    [{graffeo:vertex(), non_neg_integer()}],
    sets:set(),
    bfs_result()
) ->
    bfs_result().
bfs_loop(_Backend, _Ref, _Dir, _Filter, [], _Visited, Acc) ->
    lists:reverse(Acc);
bfs_loop(Backend, Ref, Dir, Filter, [{V, Dist} | Rest], Visited, Acc) ->
    Neighbours = directed_neighbours(Backend, Ref, Dir, V),
    Filtered = [N || N <- Neighbours, Filter(V, N), not sets:is_element(N, Visited)],
    NewVisited = lists:foldl(fun sets:add_element/2, Visited, Filtered),
    NewQueue = Rest ++ [{N, Dist + 1} || N <- Filtered],
    bfs_loop(Backend, Ref, Dir, Filter, NewQueue, NewVisited, [{V, Dist} | Acc]).

-spec directed_neighbours(module(), term(), direction(), graffeo:vertex()) ->
    [graffeo:vertex()].
directed_neighbours(Backend, Ref, out, V) ->
    Backend:out_neighbours(Ref, V);
directed_neighbours(Backend, Ref, in, V) ->
    Backend:in_neighbours(Ref, V);
directed_neighbours(Backend, Ref, both, V) ->
    lists:usort(Backend:out_neighbours(Ref, V) ++ Backend:in_neighbours(Ref, V)).
