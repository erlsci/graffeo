-module(graffeo_path).
-moduledoc """
Weighted shortest-path algorithms over the read-half behaviour.
""".

-export([
    dijkstra/3,
    dijkstra/4
]).

-type cost_fun() :: fun((graffeo:edge_meta()) -> number()).
-type dist_map() :: #{graffeo:vertex() => number()}.
-type prev_map() :: #{graffeo:vertex() => graffeo:vertex()}.

-export_type([dist_map/0, prev_map/0]).

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

%%% --- Internal ---

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
