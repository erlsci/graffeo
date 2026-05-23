-module(graffeo).
-moduledoc """
The graffeo façade: the universal algorithm layer plus Tier-1
(`graffeo_map`) constructors and operations. The one module most
users touch.
""".

-include("graffeo.hrl").

%% Tier-1 constructors (blessed front door)
-export([
    new/0,
    add_vertex/2, add_vertex/3,
    add_edge/3, add_edge/4
]).

%% Internal: envelope construction for backends
-export([wrap_ref/2]).

%% Read accessors
-export([
    vertices/1,
    out_neighbours/2,
    in_neighbours/2,
    in_degree/2,
    out_degree/2,
    no_edges/1,
    no_vertices/1,
    edge_meta/3,
    vertex_label/2
]).

%% Algorithms
-export([
    topsort/1,
    dijkstra/2,
    dijkstra/3,
    bfs/2,
    bfs/3,
    degree/2,
    degree_centrality/2,
    top_k_by_degree/2
]).

-export_type([
    graph/0,
    vertex/0,
    label/0,
    weight/0,
    edge_meta/0
]).

-opaque graph() :: #graffeo{}.

-type vertex() :: term().
-doc "Vertex label; defaults to `undefined`.".
-type label() :: term().
-doc "Numeric edge weight.".
-type weight() :: number().
-doc "Per-edge metadata: weight and optional label.".
-type edge_meta() :: #{weight => weight(), label => label()}.

%%% === Envelope construction ===

-doc false.
-spec wrap_ref(module(), term()) -> graph().
wrap_ref(Backend, Ref) ->
    #graffeo{backend = Backend, ref = Ref}.

%%% === Tier-1 constructors ===

-doc "Create a new, empty map-backed value graph.".
-spec new() -> graph().
new() ->
    wrap_ref(graffeo_map, graffeo_map:new()).

-doc "Add a vertex with the default label.".
-spec add_vertex(graph(), vertex()) -> graph().
add_vertex(#graffeo{backend = graffeo_map, ref = Ref}, V) ->
    wrap_ref(graffeo_map, graffeo_map:add_vertex(Ref, V)).

-doc "Add a vertex with a label.".
-spec add_vertex(graph(), vertex(), label()) -> graph().
add_vertex(#graffeo{backend = graffeo_map, ref = Ref}, V, Label) ->
    wrap_ref(graffeo_map, graffeo_map:add_vertex(Ref, V, Label)).

-doc "Add an edge with default metadata.".
-spec add_edge(graph(), vertex(), vertex()) -> graph().
add_edge(#graffeo{backend = graffeo_map, ref = Ref}, From, To) ->
    wrap_ref(graffeo_map, graffeo_map:add_edge(Ref, From, To)).

-doc "Add an edge with metadata (weight, label).".
-spec add_edge(graph(), vertex(), vertex(), edge_meta()) -> graph().
add_edge(#graffeo{backend = graffeo_map, ref = Ref}, From, To, Meta) ->
    wrap_ref(graffeo_map, graffeo_map:add_edge(Ref, From, To, Meta)).

%%% === Read accessors (dispatch via behaviour) ===

-doc "All vertices in the graph.".
-spec vertices(graph()) -> [vertex()].
vertices(#graffeo{backend = B, ref = R}) ->
    B:vertices(R).

-doc "Vertices reachable from `V` via outgoing edges.".
-spec out_neighbours(graph(), vertex()) -> [vertex()].
out_neighbours(#graffeo{backend = B, ref = R}, V) ->
    B:out_neighbours(R, V).

-doc "Vertices that reach `V` via incoming edges.".
-spec in_neighbours(graph(), vertex()) -> [vertex()].
in_neighbours(#graffeo{backend = B, ref = R}, V) ->
    B:in_neighbours(R, V).

-doc "Number of incoming edges to `V`.".
-spec in_degree(graph(), vertex()) -> non_neg_integer().
in_degree(#graffeo{backend = B, ref = R}, V) ->
    B:in_degree(R, V).

-doc "Number of outgoing edges from `V`.".
-spec out_degree(graph(), vertex()) -> non_neg_integer().
out_degree(#graffeo{backend = B, ref = R}, V) ->
    B:out_degree(R, V).

-doc "Total number of edges in the graph.".
-spec no_edges(graph()) -> non_neg_integer().
no_edges(#graffeo{backend = B, ref = R}) ->
    B:no_edges(R).

-doc "Total number of vertices in the graph.".
-spec no_vertices(graph()) -> non_neg_integer().
no_vertices(#graffeo{backend = B, ref = R}) ->
    B:no_vertices(R).

-doc "Get edge metadata between two vertices.".
-spec edge_meta(graph(), vertex(), vertex()) -> {ok, edge_meta()} | error.
edge_meta(#graffeo{backend = B, ref = R}, From, To) ->
    B:edge_meta(R, From, To).

-doc "Get the label of a vertex.".
-spec vertex_label(graph(), vertex()) -> {ok, label()} | error.
vertex_label(#graffeo{backend = B, ref = R}, V) ->
    B:vertex_label(R, V).

%%% === Algorithms ===

-doc """
Topological sort. Returns `{ok, Vertices}` in dependency order,
or `false` if the graph contains a cycle.
""".
-spec topsort(graph()) -> {ok, [vertex()]} | false.
topsort(#graffeo{backend = B, ref = R}) ->
    graffeo_conn:topsort(B, R, B:vertices(R)).

-doc """
Dijkstra shortest paths from `Source`, using stored edge weights.
Returns `{Distances, Predecessors}`.
""".
-spec dijkstra(graph(), vertex()) ->
    {#{vertex() => number()}, #{vertex() => vertex()}}.
dijkstra(#graffeo{backend = B, ref = R}, Source) ->
    graffeo_path:dijkstra(B, R, Source).

-doc """
Dijkstra shortest paths with options.
Options: `#{cost => fun(edge_meta()) -> number()}`.
""".
-spec dijkstra(graph(), vertex(), map()) ->
    {#{vertex() => number()}, #{vertex() => vertex()}}.
dijkstra(#graffeo{backend = B, ref = R}, Source, Opts) ->
    graffeo_path:dijkstra(B, R, Source, Opts).

-doc """
BFS from `Source` with default options (direction `out`, no filter).
Returns `[{Vertex, Distance}]`.
""".
-spec bfs(graph(), vertex()) -> [{vertex(), non_neg_integer()}].
bfs(G, Source) ->
    bfs(G, Source, #{}).

-doc """
BFS from `Source` with options.
Options: `direction` (`out`/`in`/`both`), `filter` (`fun(From, To) -> bool()`).
""".
-spec bfs(graph(), vertex(), map()) -> [{vertex(), non_neg_integer()}].
bfs(#graffeo{backend = B, ref = R}, Source, Opts) ->
    graffeo_traverse:bfs(B, R, Source, Opts).

-doc "Total degree (in + out) of vertex `V`.".
-spec degree(graph(), vertex()) -> non_neg_integer().
degree(#graffeo{backend = B, ref = R}, V) ->
    graffeo_traverse:degree(B, R, V).

-doc "Normalised degree centrality of vertex `V`.".
-spec degree_centrality(graph(), vertex()) -> float().
degree_centrality(#graffeo{backend = B, ref = R}, V) ->
    graffeo_traverse:degree_centrality(B, R, V).

-doc """
Top-k vertices by total degree, descending.
Returns `[{Vertex, Degree}]`.
""".
-spec top_k_by_degree(graph(), pos_integer()) ->
    [{vertex(), non_neg_integer()}].
top_k_by_degree(#graffeo{backend = B, ref = R}, K) ->
    graffeo_traverse:top_k_by_degree(B, R, B:vertices(R), K).
