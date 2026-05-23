-module(graffeo_digraph).
-moduledoc """
Tier-2 handle backend: transparent over stdlib `digraph`.

Presents a **simple directed graph** view: at most one edge per
ordered `(From, To)` pair. If the underlying `digraph` contains
parallel edges (e.g. via `wrap/1`), the read accessors normalize
to the simple-graph contract (last-writer-wins for metadata).
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

-doc """
Add an edge with default metadata.

If a `From→To` edge already exists, its metadata is replaced
(simple-graph contract: at most one edge per ordered pair).
""".
-spec add_edge(digraph:graph(), graffeo:vertex(), graffeo:vertex()) -> ok.
add_edge(Ref, From, To) ->
    add_edge(Ref, From, To, #{weight => 1}).

-doc """
Add an edge with metadata (stored as the edge label).

If a `From→To` edge already exists, it is replaced with the new
metadata (last-writer-wins, simple-graph contract).
""".
-spec add_edge(
    digraph:graph(), graffeo:vertex(), graffeo:vertex(), graffeo:edge_meta()
) -> ok.
add_edge(Ref, From, To, Meta) ->
    digraph:add_vertex(Ref, From),
    digraph:add_vertex(Ref, To),
    remove_edges(Ref, From, To),
    digraph:add_edge(Ref, From, To, Meta),
    ok.

%%% === graffeo_backend callbacks ===

-doc "All vertices in the graph.".
-spec vertices(digraph:graph()) -> [graffeo:vertex()].
vertices(Ref) ->
    digraph:vertices(Ref).

-doc "Vertices reachable from `V` via outgoing edges (deduplicated).".
-spec out_neighbours(digraph:graph(), graffeo:vertex()) -> [graffeo:vertex()].
out_neighbours(Ref, V) ->
    lists:usort(digraph:out_neighbours(Ref, V)).

-doc "Vertices that reach `V` via incoming edges (deduplicated).".
-spec in_neighbours(digraph:graph(), graffeo:vertex()) -> [graffeo:vertex()].
in_neighbours(Ref, V) ->
    lists:usort(digraph:in_neighbours(Ref, V)).

-doc "Number of distinct incoming neighbours of `V`.".
-spec in_degree(digraph:graph(), graffeo:vertex()) -> non_neg_integer().
in_degree(Ref, V) ->
    length(in_neighbours(Ref, V)).

-doc "Number of distinct outgoing neighbours of `V`.".
-spec out_degree(digraph:graph(), graffeo:vertex()) -> non_neg_integer().
out_degree(Ref, V) ->
    length(out_neighbours(Ref, V)).

-doc "Total number of distinct `(From, To)` edges in the graph.".
-spec no_edges(digraph:graph()) -> non_neg_integer().
no_edges(Ref) ->
    distinct_edge_count(Ref).

-doc "Total number of vertices in the graph.".
-spec no_vertices(digraph:graph()) -> non_neg_integer().
no_vertices(Ref) ->
    digraph:no_vertices(Ref).

%%% === Extra accessors ===

-doc """
Get edge metadata between two vertices.

If parallel edges exist (e.g. from a wrapped raw `digraph`),
returns the metadata of the highest-numbered edge (last-writer-wins).
""".
-spec edge_meta(digraph:graph(), graffeo:vertex(), graffeo:vertex()) ->
    {ok, graffeo:edge_meta()} | error.
edge_meta(Ref, From, To) ->
    Edges = digraph:out_edges(Ref, From),
    find_last_edge_meta(Ref, Edges, To).

-doc "Get the label of a vertex.".
-spec vertex_label(digraph:graph(), graffeo:vertex()) ->
    {ok, graffeo:label()} | error.
vertex_label(Ref, V) ->
    case digraph:vertex(Ref, V) of
        {V, Label} -> {ok, Label};
        false -> error
    end.

%%% --- Internal ---

-spec remove_edges(digraph:graph(), graffeo:vertex(), graffeo:vertex()) -> ok.
remove_edges(Ref, From, To) ->
    Edges = digraph:out_edges(Ref, From),
    lists:foreach(
        fun(E) ->
            case digraph:edge(Ref, E) of
                {E, From, To, _Meta} -> digraph:del_edge(Ref, E);
                _ -> ok
            end
        end,
        Edges
    ).

-spec find_last_edge_meta(digraph:graph(), [digraph:edge()], graffeo:vertex()) ->
    {ok, graffeo:edge_meta()} | error.
find_last_edge_meta(Ref, Edges, To) ->
    Matching = [
        {E, Meta}
     || E <- Edges,
        {E1, _From, To1, Meta} <- [digraph:edge(Ref, E)],
        E1 =:= E,
        To1 =:= To
    ],
    case Matching of
        [] ->
            error;
        _ ->
            {_, Meta} = lists:last(Matching),
            {ok, Meta}
    end.

-spec distinct_edge_count(digraph:graph()) -> non_neg_integer().
distinct_edge_count(Ref) ->
    Pairs = lists:usort([
        {From, To}
     || E <- digraph:edges(Ref),
        {E1, From, To, _} <- [digraph:edge(Ref, E)],
        E1 =:= E
    ]),
    length(Pairs).
