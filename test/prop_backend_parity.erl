-module(prop_backend_parity).
-moduledoc """
PropEr parity properties: random edge list → both backends →
read-half and algorithm parity.
""".

-include_lib("proper/include/proper.hrl").

-export([prop_read_half_parity/0, prop_topsort_parity/0]).

prop_read_half_parity() ->
    ?FORALL(
        Edges,
        edge_list(),
        begin
            {MapG, DigraphG, DRef} = build_both(Edges),
            Result = check_read_parity(MapG, DigraphG),
            digraph:delete(DRef),
            Result
        end
    ).

prop_topsort_parity() ->
    ?FORALL(
        Edges,
        dag_edge_list(),
        begin
            {MapG, DigraphG, DRef} = build_both(Edges),
            MapTS = graffeo:topsort(MapG),
            DigTS = graffeo:topsort(DigraphG),
            Result =
                case {MapTS, DigTS} of
                    {{ok, MapOrder}, {ok, DigOrder}} ->
                        length(MapOrder) =:= length(DigOrder);
                    {false, false} ->
                        true;
                    _ ->
                        false
                end,
            digraph:delete(DRef),
            Result
        end
    ).

%%% --- generators ---

edge_list() ->
    ?LET(
        Edges,
        list({vertex_gen(), vertex_gen(), pos_integer()}),
        dedup_edges(Edges)
    ).

dag_edge_list() ->
    ?LET(
        Edges,
        list({integer(1, 20), integer(1, 20), pos_integer()}),
        [{From, To, W} || {From, To, W} <- Edges, From < To]
    ).

vertex_gen() ->
    oneof([a, b, c, d, e, f, g, h]).

%%% --- helpers ---

build_both(Edges) ->
    MapG = lists:foldl(
        fun({From, To, W}, G) ->
            graffeo:add_edge(G, From, To, #{weight => W})
        end,
        graffeo:new(),
        Edges
    ),
    D = digraph:new(),
    lists:foreach(
        fun({From, To, W}) ->
            digraph:add_vertex(D, From),
            digraph:add_vertex(D, To),
            digraph:add_edge(D, From, To, #{weight => W})
        end,
        Edges
    ),
    DigraphG = graffeo_digraph:wrap(D),
    {MapG, DigraphG, D}.

dedup_edges(Edges) ->
    dedup_edges(Edges, sets:new([{version, 2}]), []).

dedup_edges([], _Seen, Acc) ->
    lists:reverse(Acc);
dedup_edges([{F, T, W} | Rest], Seen, Acc) ->
    Key = {F, T},
    case sets:is_element(Key, Seen) of
        true -> dedup_edges(Rest, Seen, Acc);
        false -> dedup_edges(Rest, sets:add_element(Key, Seen), [{F, T, W} | Acc])
    end.

check_read_parity(MapG, DigraphG) ->
    MapVerts = lists:sort(graffeo:vertices(MapG)),
    DigVerts = lists:sort(graffeo:vertices(DigraphG)),
    MapVerts =:= DigVerts andalso
        graffeo:no_vertices(MapG) =:= graffeo:no_vertices(DigraphG) andalso
        graffeo:no_edges(MapG) =:= graffeo:no_edges(DigraphG) andalso
        lists:all(
            fun(V) ->
                lists:sort(graffeo:out_neighbours(MapG, V)) =:=
                    lists:sort(graffeo:out_neighbours(DigraphG, V)) andalso
                    lists:sort(graffeo:in_neighbours(MapG, V)) =:=
                        lists:sort(graffeo:in_neighbours(DigraphG, V)) andalso
                    graffeo:in_degree(MapG, V) =:= graffeo:in_degree(DigraphG, V) andalso
                    graffeo:out_degree(MapG, V) =:= graffeo:out_degree(DigraphG, V)
            end,
            MapVerts
        ).
