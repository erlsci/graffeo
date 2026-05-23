-module(graffeo_digraph).
-moduledoc """
Tier-2 handle backend: transparent over stdlib `digraph`. Operations
mutate in place; the graph is a handle, not a value.
""".

-behaviour(graffeo_backend).
-behaviour(graffeo_builder).

%% Construction
-export([
    new/0,
    wrap/1,
    add_vertex/2, add_vertex/3,
    add_edge/3, add_edge/4
]).

%% Read (graffeo_backend)
-export([
    vertices/1,
    out_neighbours/2,
    in_neighbours/2,
    in_degree/2,
    out_degree/2,
    no_edges/1,
    no_vertices/1
]).

%% Extra accessors
-export([
    edge_meta/3,
    vertex_label/2
]).

%%% === Construction ===

-doc "Create a new, empty digraph handle wrapped in a graffeo envelope.".
-spec new() -> graffeo:graph().
new() ->
    Ref = digraph:new(),
    graffeo:wrap_ref(?MODULE, Ref).

-doc "Lift a bare `digraph` handle into a graffeo envelope.".
-spec wrap(digraph:graph()) -> graffeo:graph().
wrap(Ref) ->
    graffeo:wrap_ref(?MODULE, Ref).

-doc "Add a vertex with the default label.".
-spec add_vertex(digraph:graph(), graffeo:vertex()) -> ok.
add_vertex(Ref, V) ->
    digraph:add_vertex(Ref, V),
    ok.

-doc "Add a vertex with a label.".
-spec add_vertex(digraph:graph(), graffeo:vertex(), graffeo:label()) -> ok.
add_vertex(Ref, V, Label) ->
    digraph:add_vertex(Ref, V, Label),
    ok.

-doc "Add an edge with default metadata.".
-spec add_edge(digraph:graph(), graffeo:vertex(), graffeo:vertex()) -> ok.
add_edge(Ref, From, To) ->
    add_edge(Ref, From, To, #{weight => 1}).

-doc "Add an edge with metadata (stored as the edge label).".
-spec add_edge(
    digraph:graph(), graffeo:vertex(), graffeo:vertex(), graffeo:edge_meta()
) -> ok.
add_edge(Ref, From, To, Meta) ->
    digraph:add_vertex(Ref, From),
    digraph:add_vertex(Ref, To),
    digraph:add_edge(Ref, From, To, Meta),
    ok.

%%% === graffeo_backend callbacks ===

-doc "All vertices in the graph.".
-spec vertices(digraph:graph()) -> [graffeo:vertex()].
vertices(Ref) ->
    digraph:vertices(Ref).

-doc "Vertices reachable from `V` via outgoing edges.".
-spec out_neighbours(digraph:graph(), graffeo:vertex()) -> [graffeo:vertex()].
out_neighbours(Ref, V) ->
    digraph:out_neighbours(Ref, V).

-doc "Vertices that reach `V` via incoming edges.".
-spec in_neighbours(digraph:graph(), graffeo:vertex()) -> [graffeo:vertex()].
in_neighbours(Ref, V) ->
    digraph:in_neighbours(Ref, V).

-doc "Number of incoming edges to `V`.".
-spec in_degree(digraph:graph(), graffeo:vertex()) -> non_neg_integer().
in_degree(Ref, V) ->
    digraph:in_degree(Ref, V).

-doc "Number of outgoing edges from `V`.".
-spec out_degree(digraph:graph(), graffeo:vertex()) -> non_neg_integer().
out_degree(Ref, V) ->
    digraph:out_degree(Ref, V).

-doc "Total number of edges in the graph.".
-spec no_edges(digraph:graph()) -> non_neg_integer().
no_edges(Ref) ->
    digraph:no_edges(Ref).

-doc "Total number of vertices in the graph.".
-spec no_vertices(digraph:graph()) -> non_neg_integer().
no_vertices(Ref) ->
    digraph:no_vertices(Ref).

%%% === Extra accessors ===

-doc "Get edge metadata between two vertices.".
-spec edge_meta(digraph:graph(), graffeo:vertex(), graffeo:vertex()) ->
    {ok, graffeo:edge_meta()} | error.
edge_meta(Ref, From, To) ->
    Edges = digraph:out_edges(Ref, From),
    find_edge_meta(Ref, Edges, To).

-doc "Get the label of a vertex.".
-spec vertex_label(digraph:graph(), graffeo:vertex()) ->
    {ok, graffeo:label()} | error.
vertex_label(Ref, V) ->
    case digraph:vertex(Ref, V) of
        {V, Label} -> {ok, Label};
        false -> error
    end.

%%% --- Internal ---

-spec find_edge_meta(digraph:graph(), [digraph:edge()], graffeo:vertex()) ->
    {ok, graffeo:edge_meta()} | error.
find_edge_meta(_Ref, [], _To) ->
    error;
find_edge_meta(Ref, [E | Rest], To) ->
    case digraph:edge(Ref, E) of
        {E, _From, To, Meta} -> {ok, Meta};
        _ -> find_edge_meta(Ref, Rest, To)
    end.
