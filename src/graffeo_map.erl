-module(graffeo_map).
-moduledoc """
Tier-1 value backend: an immutable, maps-backed graph with dual
adjacency. Every operation returns a new graph; the original is
untouched. Labels on vertices, weight/metadata on edges.
""".

-behaviour(graffeo_backend).
-behaviour(graffeo_builder).

-export([
    new/0,
    add_vertex/2, add_vertex/3,
    add_edge/3, add_edge/4,
    edge_meta/3,
    vertex_label/2
]).

%% graffeo_builder callbacks (envelope-based)
-export([
    empty_like/1,
    build_add_vertex/2, build_add_vertex/3,
    build_add_edge/4
]).

-export([
    vertices/1,
    out_neighbours/2,
    in_neighbours/2,
    in_degree/2,
    out_degree/2,
    no_edges/1,
    no_vertices/1
]).

-record(gmap, {
    vs = #{} :: #{graffeo:vertex() => graffeo:label()},
    out = #{} :: #{graffeo:vertex() => #{graffeo:vertex() => graffeo:edge_meta()}},
    in = #{} :: #{graffeo:vertex() => #{graffeo:vertex() => graffeo:edge_meta()}}
}).

-opaque ref() :: #gmap{}.
-export_type([ref/0]).

%%% --- graffeo_builder callbacks ---

-doc "Create a new, empty map-backed graph.".
-spec new() -> ref().
new() ->
    #gmap{}.

-doc "Add a vertex with the default label (`undefined`).".
-spec add_vertex(ref(), graffeo:vertex()) -> ref().
add_vertex(G, V) ->
    add_vertex(G, V, undefined).

-doc "Add a vertex with a label.".
-spec add_vertex(ref(), graffeo:vertex(), graffeo:label()) -> ref().
add_vertex(#gmap{vs = Vs, out = Out, in = In} = G, V, Label) ->
    G#gmap{
        vs = Vs#{V => Label},
        out = maps:merge(#{V => #{}}, Out),
        in = maps:merge(#{V => #{}}, In)
    }.

-doc "Add an edge with default metadata (`#{weight => 1}`).".
-spec add_edge(ref(), graffeo:vertex(), graffeo:vertex()) -> ref().
add_edge(G, From, To) ->
    add_edge(G, From, To, #{weight => 1}).

-doc "Add an edge with metadata (weight, label).".
-spec add_edge(ref(), graffeo:vertex(), graffeo:vertex(), graffeo:edge_meta()) -> ref().
add_edge(G0, From, To, Meta) ->
    G1 = ensure_vertex(G0, From),
    G2 = ensure_vertex(G1, To),
    #gmap{out = Out, in = In} = G2,
    OutFrom = maps:get(From, Out),
    InTo = maps:get(To, In),
    G2#gmap{
        out = Out#{From := OutFrom#{To => Meta}},
        in = In#{To := InTo#{From => Meta}}
    }.

%%% --- graffeo_backend callbacks ---

-doc "All vertices in the graph.".
-spec vertices(ref()) -> [graffeo:vertex()].
vertices(#gmap{vs = Vs}) ->
    maps:keys(Vs).

-doc "Vertices reachable from `V` via outgoing edges.".
-spec out_neighbours(ref(), graffeo:vertex()) -> [graffeo:vertex()].
out_neighbours(#gmap{out = Out}, V) ->
    maps:keys(maps:get(V, Out, #{})).

-doc "Vertices that reach `V` via incoming edges.".
-spec in_neighbours(ref(), graffeo:vertex()) -> [graffeo:vertex()].
in_neighbours(#gmap{in = In}, V) ->
    maps:keys(maps:get(V, In, #{})).

-doc "Number of incoming edges to `V`.".
-spec in_degree(ref(), graffeo:vertex()) -> non_neg_integer().
in_degree(#gmap{in = In}, V) ->
    map_size(maps:get(V, In, #{})).

-doc "Number of outgoing edges from `V`.".
-spec out_degree(ref(), graffeo:vertex()) -> non_neg_integer().
out_degree(#gmap{out = Out}, V) ->
    map_size(maps:get(V, Out, #{})).

-doc "Total number of edges in the graph.".
-spec no_edges(ref()) -> non_neg_integer().
no_edges(#gmap{out = Out}) ->
    maps:fold(fun(_V, Adj, Acc) -> Acc + map_size(Adj) end, 0, Out).

-doc "Total number of vertices in the graph.".
-spec no_vertices(ref()) -> non_neg_integer().
no_vertices(#gmap{vs = Vs}) ->
    map_size(Vs).

%%% --- Extra accessors ---

-doc "Get edge metadata between two vertices.".
-spec edge_meta(ref(), graffeo:vertex(), graffeo:vertex()) ->
    {ok, graffeo:edge_meta()} | error.
edge_meta(#gmap{out = Out}, From, To) ->
    case maps:find(From, Out) of
        {ok, Adj} -> maps:find(To, Adj);
        error -> error
    end.

-doc "Get the label of a vertex.".
-spec vertex_label(ref(), graffeo:vertex()) ->
    {ok, graffeo:label()} | error.
vertex_label(#gmap{vs = Vs}, V) ->
    maps:find(V, Vs).

%%% --- graffeo_builder callbacks (envelope-based) ---

-doc false.
-spec empty_like(graffeo:graph()) -> graffeo:graph().
empty_like(_G) ->
    graffeo:wrap_ref(graffeo_map, new()).

-doc false.
-spec build_add_vertex(graffeo:graph(), graffeo:vertex()) -> graffeo:graph().
build_add_vertex(G, V) ->
    build_add_vertex(G, V, []).

-doc false.
-spec build_add_vertex(graffeo:graph(), graffeo:vertex(), graffeo:label()) -> graffeo:graph().
build_add_vertex(G, V, Label) ->
    graffeo:add_vertex(G, V, Label).

-doc false.
-spec build_add_edge(graffeo:graph(), graffeo:vertex(), graffeo:vertex(), graffeo:edge_meta()) ->
    graffeo:graph().
build_add_edge(G, From, To, Meta) ->
    graffeo:add_edge(G, From, To, Meta).

%%% --- Internal ---

-spec ensure_vertex(ref(), graffeo:vertex()) -> ref().
ensure_vertex(#gmap{vs = Vs} = G, V) ->
    case maps:is_key(V, Vs) of
        true -> G;
        false -> add_vertex(G, V)
    end.
