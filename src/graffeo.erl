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

%% Internal: envelope access for backends
-export([wrap_ref/2, extract_ref/2, backend/1]).

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
    astar/3,
    astar/4,
    bfs/2,
    bfs/3,
    degree/2,
    degree_centrality/2,
    top_k_by_degree/2
]).

%% Constructive algorithms
-export([
    subgraph/2, subgraph/3,
    condensation/1
]).

%% Path/cycle queries (ported from digraph)
-export([
    get_path/3,
    get_cycle/2,
    get_short_path/3,
    get_short_cycle/2,
    source_vertices/1,
    sink_vertices/1
]).

%% Connectivity / DFS-family (ported from digraph_utils)
-export([
    components/1,
    strong_components/1,
    cyclic_strong_components/1,
    reachable/2,
    reachable_neighbours/2,
    reaching/2,
    reaching_neighbours/2,
    is_acyclic/1,
    loop_vertices/1,
    preorder/1,
    postorder/1,
    is_tree/1,
    is_arborescence/1,
    arborescence_root/1
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

-doc false.
-spec extract_ref(module(), graph()) -> term().
extract_ref(Expected, #graffeo{backend = Expected, ref = Ref}) ->
    Ref;
extract_ref(Expected, #graffeo{backend = Actual}) ->
    erlang:error({backend_mismatch, Expected, Actual}).

-doc false.
-spec backend(graph()) -> module().
backend(#graffeo{backend = B}) ->
    B.

%%% === Tier-1 constructors ===

-doc "Create a new, empty map-backed value graph.".
-spec new() -> graph().
new() ->
    wrap_ref(graffeo_map, graffeo_map:new()).

-doc """
Add a vertex with the default label.

Tier-1 operation — only valid on map-backed graphs.
For handle-backed graphs, use `graffeo_digraph:add_vertex/2`.
""".
-spec add_vertex(graph(), vertex()) -> graph().
add_vertex(#graffeo{backend = graffeo_map, ref = Ref}, V) ->
    wrap_ref(graffeo_map, graffeo_map:add_vertex(Ref, V));
add_vertex(#graffeo{backend = Backend}, _V) ->
    erlang:error({tier1_only, add_vertex, Backend}).

-doc """
Add a vertex with a label.

Tier-1 operation — only valid on map-backed graphs.
For handle-backed graphs, use `graffeo_digraph:add_vertex/3`.
""".
-spec add_vertex(graph(), vertex(), label()) -> graph().
add_vertex(#graffeo{backend = graffeo_map, ref = Ref}, V, Label) ->
    wrap_ref(graffeo_map, graffeo_map:add_vertex(Ref, V, Label));
add_vertex(#graffeo{backend = Backend}, _V, _Label) ->
    erlang:error({tier1_only, add_vertex, Backend}).

-doc """
Add an edge with default metadata.

Tier-1 operation — only valid on map-backed graphs.
For handle-backed graphs, use `graffeo_digraph:add_edge/3`.
""".
-spec add_edge(graph(), vertex(), vertex()) -> graph().
add_edge(#graffeo{backend = graffeo_map, ref = Ref}, From, To) ->
    wrap_ref(graffeo_map, graffeo_map:add_edge(Ref, From, To));
add_edge(#graffeo{backend = Backend}, _From, _To) ->
    erlang:error({tier1_only, add_edge, Backend}).

-doc """
Add an edge with metadata (weight, label).

Tier-1 operation — only valid on map-backed graphs.
For handle-backed graphs, use `graffeo_digraph:add_edge/4`.
""".
-spec add_edge(graph(), vertex(), vertex(), edge_meta()) -> graph().
add_edge(#graffeo{backend = graffeo_map, ref = Ref}, From, To, Meta) ->
    wrap_ref(graffeo_map, graffeo_map:add_edge(Ref, From, To, Meta));
add_edge(#graffeo{backend = Backend}, _From, _To, _Meta) ->
    erlang:error({tier1_only, add_edge, Backend}).

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

**Precondition:** all edge costs must be non-negative. Negative costs
produce undefined results. For negative-weight graphs, use a future
Bellman-Ford (not yet implemented).
""".
-spec dijkstra(graph(), vertex()) ->
    {#{vertex() => number()}, #{vertex() => vertex()}}.
dijkstra(#graffeo{backend = B, ref = R}, Source) ->
    graffeo_path:dijkstra(B, R, Source).

-doc """
Dijkstra shortest paths with options.
Options: `#{cost => fun(edge_meta()) -> number()}`.

**Precondition:** the cost function must return non-negative values.
Negative costs produce undefined results.
""".
-spec dijkstra(graph(), vertex(), map()) ->
    {#{vertex() => number()}, #{vertex() => vertex()}}.
dijkstra(#graffeo{backend = B, ref = R}, Source, Opts) ->
    graffeo_path:dijkstra(B, R, Source, Opts).

-doc """
A* shortest path from `Source` to `Target`, using stored edge weights.
Returns `{ok, Path, Cost}` or `none` if unreachable.

With the default zero heuristic, degenerates to Dijkstra.

**Preconditions:** costs must be non-negative; the heuristic must be
admissible (never overestimate) for the result to be optimal.
""".
-spec astar(graph(), vertex(), vertex()) ->
    {ok, [vertex()], number()} | none.
astar(#graffeo{backend = B, ref = R}, Source, Target) ->
    graffeo_path:astar(B, R, Source, Target, B:vertices(R)).

-doc """
A* shortest path with options.
Options: `#{cost => fun(edge_meta()) -> number(), heuristic => fun(vertex()) -> number()}`.
""".
-spec astar(graph(), vertex(), vertex(), map()) ->
    {ok, [vertex()], number()} | none.
astar(#graffeo{backend = B, ref = R}, Source, Target, Opts) ->
    graffeo_path:astar(B, R, Source, Target, B:vertices(R), Opts).

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

%%% === Connectivity / DFS-family ===

-doc "Connected components (undirected). Returns `[[vertex()]]`.".
-spec components(graph()) -> [[vertex()]].
components(#graffeo{backend = B, ref = R}) ->
    graffeo_conn:components(B, R, B:vertices(R)).

-doc "Strongly connected components. Returns `[[vertex()]]`.".
-spec strong_components(graph()) -> [[vertex()]].
strong_components(#graffeo{backend = B, ref = R}) ->
    graffeo_conn:strong_components(B, R, B:vertices(R)).

-doc "Strongly connected components that contain a cycle.".
-spec cyclic_strong_components(graph()) -> [[vertex()]].
cyclic_strong_components(#graffeo{backend = B, ref = R}) ->
    graffeo_conn:cyclic_strong_components(B, R, B:vertices(R)).

-doc "Vertices reachable from `Vs` (including `Vs`).".
-spec reachable(graph(), [vertex()]) -> [vertex()].
reachable(#graffeo{backend = B, ref = R}, Vs) ->
    graffeo_conn:reachable(B, R, B:vertices(R), Vs).

-doc "Vertices reachable from `Vs` (excluding `Vs` unless in a cycle).".
-spec reachable_neighbours(graph(), [vertex()]) -> [vertex()].
reachable_neighbours(#graffeo{backend = B, ref = R}, Vs) ->
    graffeo_conn:reachable_neighbours(B, R, B:vertices(R), Vs).

-doc "Vertices from which `Vs` are reachable (including `Vs`).".
-spec reaching(graph(), [vertex()]) -> [vertex()].
reaching(#graffeo{backend = B, ref = R}, Vs) ->
    graffeo_conn:reaching(B, R, B:vertices(R), Vs).

-doc "Vertices from which `Vs` are reachable (excluding `Vs` unless in a cycle).".
-spec reaching_neighbours(graph(), [vertex()]) -> [vertex()].
reaching_neighbours(#graffeo{backend = B, ref = R}, Vs) ->
    graffeo_conn:reaching_neighbours(B, R, B:vertices(R), Vs).

-doc "True if the graph is acyclic (no cycles).".
-spec is_acyclic(graph()) -> boolean().
is_acyclic(#graffeo{backend = B, ref = R}) ->
    graffeo_conn:is_acyclic(B, R, B:vertices(R)).

-doc "Vertices with a self-loop.".
-spec loop_vertices(graph()) -> [vertex()].
loop_vertices(#graffeo{backend = B, ref = R}) ->
    graffeo_conn:loop_vertices(B, R, B:vertices(R)).

-doc "Vertices in DFS preorder.".
-spec preorder(graph()) -> [vertex()].
preorder(#graffeo{backend = B, ref = R}) ->
    graffeo_conn:preorder(B, R, B:vertices(R)).

-doc "Vertices in DFS postorder.".
-spec postorder(graph()) -> [vertex()].
postorder(#graffeo{backend = B, ref = R}) ->
    graffeo_conn:postorder(B, R, B:vertices(R)).

-doc "True if the graph is a tree (undirected, connected, acyclic).".
-spec is_tree(graph()) -> boolean().
is_tree(#graffeo{backend = B, ref = R}) ->
    graffeo_conn:is_tree(B, R, B:vertices(R)).

-doc "True if the graph is an arborescence (rooted tree, directed).".
-spec is_arborescence(graph()) -> boolean().
is_arborescence(#graffeo{backend = B, ref = R}) ->
    graffeo_conn:is_arborescence(B, R, B:vertices(R)).

-doc "Returns `{yes, Root}` if the graph is an arborescence, `no` otherwise.".
-spec arborescence_root(graph()) -> {yes, vertex()} | no.
arborescence_root(#graffeo{backend = B, ref = R}) ->
    graffeo_conn:arborescence_root(B, R, B:vertices(R)).

%%% === Constructive algorithms ===

-doc """
Induced subgraph over the given vertices.

Returns a new graph (same backend) with only the listed vertices
and edges where both endpoints are in the list.

**Tier-2 lifecycle:** over a handle graph, the result is a new
handle the caller must `graffeo_digraph:delete/1`.
""".
-spec subgraph(graph(), [vertex()]) -> graph().
subgraph(G, SubVs) ->
    subgraph(G, SubVs, []).

-doc """
Induced subgraph with options.

Options: `{keep_labels, boolean()}` (default `true`),
`{type, inherit | [d_type()]}` (handle backend only; ignored for value).
Raises `badarg` on malformed options.
""".
-spec subgraph(graph(), [vertex()], list()) -> graph().
subgraph(#graffeo{backend = B, ref = R} = G, SubVs, Opts) ->
    graffeo_conn:subgraph(G, B, R, SubVs, Opts).

-doc """
Condensation: one vertex per strongly connected component.

Each vertex in the result is the member-list of a SCC. An edge
exists where any cross-component edge exists in the original.

**Tier-2 lifecycle:** over a handle graph, the result is a new
handle the caller must `graffeo_digraph:delete/1`.
""".
-spec condensation(graph()) -> graph().
condensation(#graffeo{backend = B, ref = R} = G) ->
    graffeo_conn:condensation(B, R, G, B:vertices(R)).

%%% === Path/cycle queries ===

-doc "DFS path from `V1` to `V2`, or `false`.".
-spec get_path(graph(), vertex(), vertex()) -> [vertex()] | false.
get_path(#graffeo{backend = B, ref = R}, V1, V2) ->
    graffeo_path:get_path(B, R, V1, V2).

-doc "A cycle through `V` (DFS), or `false`.".
-spec get_cycle(graph(), vertex()) -> [vertex()] | false.
get_cycle(#graffeo{backend = B, ref = R}, V) ->
    graffeo_path:get_cycle(B, R, V).

-doc """
Shortest (fewest-edges) path from `V1` to `V2` (BFS), or `false`.

When `V1 =:= V2`, returns the shortest cycle through `V`.
This is an **unweighted** path — edge weights are ignored.
""".
-spec get_short_path(graph(), vertex(), vertex()) -> [vertex()] | false.
get_short_path(#graffeo{backend = B, ref = R}, V1, V2) ->
    graffeo_path:get_short_path(B, R, V1, V2).

-doc "Shortest cycle through `V` (BFS), or `false`.".
-spec get_short_cycle(graph(), vertex()) -> [vertex()] | false.
get_short_cycle(#graffeo{backend = B, ref = R}, V) ->
    graffeo_path:get_short_cycle(B, R, V).

-doc "Vertices with in-degree 0.".
-spec source_vertices(graph()) -> [vertex()].
source_vertices(#graffeo{backend = B, ref = R}) ->
    [V || V <- B:vertices(R), B:in_degree(R, V) =:= 0].

-doc "Vertices with out-degree 0.".
-spec sink_vertices(graph()) -> [vertex()].
sink_vertices(#graffeo{backend = B, ref = R}) ->
    [V || V <- B:vertices(R), B:out_degree(R, V) =:= 0].
