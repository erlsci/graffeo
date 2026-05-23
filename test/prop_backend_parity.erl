-module(prop_backend_parity).
-moduledoc """
PropEr parity properties: random edge list → both backends →
read-half and algorithm parity.
""".

-include_lib("proper/include/proper.hrl").

-export([
    prop_read_half_parity/0,
    prop_topsort_parity/0,
    prop_components_stdlib_parity/0,
    prop_get_short_path_stdlib_parity/0
]).

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
                        length(MapOrder) =:= length(DigOrder) andalso
                            is_valid_topsort(MapG, MapOrder) andalso
                            is_valid_topsort(DigraphG, DigOrder);
                    {false, false} ->
                        true;
                    _ ->
                        false
                end,
            digraph:delete(DRef),
            Result
        end
    ).

prop_components_stdlib_parity() ->
    ?FORALL(
        Edges,
        edge_list(),
        begin
            {_MapG, DigraphG, DRef} = build_both(Edges),
            StdLib = digraph_utils:components(DRef),
            Graffeo = graffeo:components(DigraphG),
            Result = StdLib =:= Graffeo,
            digraph:delete(DRef),
            Result
        end
    ).

prop_get_short_path_stdlib_parity() ->
    ?FORALL(
        {Edges, V1, V2},
        {edge_list(), vertex_gen(), vertex_gen()},
        begin
            {_MapG, DigraphG, DRef} = build_both(Edges),
            StdLib = digraph:get_short_path(DRef, V1, V2),
            Graffeo = graffeo:get_short_path(DigraphG, V1, V2),
            Result =
                case {StdLib, Graffeo} of
                    {false, false} ->
                        true;
                    {SL, GR} when is_list(SL), is_list(GR) ->
                        length(SL) =:= length(GR) andalso
                            hd(SL) =:= hd(GR) andalso
                            lists:last(SL) =:= lists:last(GR) andalso
                            is_valid_path(DigraphG, GR);
                    _ ->
                        false
                end,
            digraph:delete(DRef),
            Result
        end
    ).

%%% --- generators ---

edge_list() ->
    list({vertex_gen(), vertex_gen(), pos_integer()}).

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

is_valid_topsort(G, Order) ->
    Pos = maps:from_list(lists:zip(Order, lists:seq(1, length(Order)))),
    lists:all(
        fun(V) ->
            VPos = maps:get(V, Pos),
            lists:all(
                fun(N) -> maps:get(N, Pos) > VPos end,
                graffeo:out_neighbours(G, V)
            )
        end,
        graffeo:vertices(G)
    ).

is_valid_path(_G, [_]) ->
    true;
is_valid_path(G, [V, W | Rest]) ->
    lists:member(W, graffeo:out_neighbours(G, V)) andalso
        is_valid_path(G, [W | Rest]).

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
