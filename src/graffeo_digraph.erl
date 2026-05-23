-module(graffeo_digraph).
-moduledoc """
Tier-2 handle backend: transparent over stdlib `digraph`.

Construction, mutation, and lifecycle operate on the opaque
`graffeo:graph()` envelope. Presents a **simple directed graph**
view: at most one edge per ordered `(From, To)` pair.
""".

-behaviour(graffeo_backend).
-behaviour(graffeo_builder).

-include("graffeo.hrl").

%% Construction / lifecycle (envelope-based)
-export([
    new/0,
    wrap/1,
    unwrap/1,
    delete/1
]).

%% Mutation (envelope-based, mutate-in-place)
-export([
    add_vertex/2, add_vertex/3,
    add_edge/3, add_edge/4,
    del_vertex/2,
    del_vertices/2,
    del_edge/3,
    del_edges/2
]).

%% Read (graffeo_backend, bare-ref)
-export([
    vertices/1,
    out_neighbours/2,
    in_neighbours/2,
    in_degree/2,
    out_degree/2,
    no_edges/1,
    no_vertices/1
]).

%% Extra accessors (bare-ref)
-export([
    edge_meta/3,
    vertex_label/2
]).

%% graffeo_builder callbacks (envelope-based)
-export([
    empty_like/1,
    build_add_vertex/2, build_add_vertex/3,
    build_add_edge/4
]).

%%% === Construction / lifecycle ===

-doc "Create a new, empty digraph handle wrapped in a graffeo envelope.".
-spec new() -> graffeo:graph().
new() ->
    Ref = digraph:new(),
    graffeo:wrap_ref(?MODULE, Ref).

-doc "Lift a bare `digraph` handle into a graffeo envelope.".
-spec wrap(digraph:graph()) -> graffeo:graph().
wrap(Ref) ->
    graffeo:wrap_ref(?MODULE, Ref).

-doc """
Hand back the bare `digraph` handle from the envelope.

The explicit escape hatch for users who need raw `digraph:*` access.
""".
-spec unwrap(graffeo:graph()) -> digraph:graph().
unwrap(G) ->
    require_handle(unwrap, G).

-doc """
Free the underlying digraph handle (ETS tables).

Use-after-delete is undefined.
""".
-spec delete(graffeo:graph()) -> ok.
delete(G) ->
    D = require_handle(delete, G),
    digraph:delete(D),
    ok.

%%% === Mutation (envelope-based) ===

-doc "Add a vertex with the default label.".
-spec add_vertex(graffeo:graph(), graffeo:vertex()) -> ok.
add_vertex(G, V) ->
    D = require_handle(add_vertex, G),
    digraph:add_vertex(D, V),
    ok.

-doc "Add a vertex with a label.".
-spec add_vertex(graffeo:graph(), graffeo:vertex(), graffeo:label()) -> ok.
add_vertex(G, V, Label) ->
    D = require_handle(add_vertex, G),
    digraph:add_vertex(D, V, Label),
    ok.

-doc """
Add an edge with default metadata.

If a `From→To` edge already exists, its metadata is replaced
(simple-graph contract: at most one edge per ordered pair).
""".
-spec add_edge(graffeo:graph(), graffeo:vertex(), graffeo:vertex()) -> ok.
add_edge(G, From, To) ->
    add_edge(G, From, To, #{weight => 1}).

-doc """
Add an edge with metadata (stored as the edge label).

If a `From→To` edge already exists, it is replaced with the new
metadata (last-writer-wins, simple-graph contract).
""".
-spec add_edge(
    graffeo:graph(), graffeo:vertex(), graffeo:vertex(), graffeo:edge_meta()
) -> ok.
add_edge(G, From, To, Meta) ->
    D = require_handle(add_edge, G),
    digraph:add_vertex(D, From),
    digraph:add_vertex(D, To),
    remove_edges(D, From, To),
    digraph:add_edge(D, From, To, Meta),
    ok.

-doc "Remove vertex `V` and all its incident edges.".
-spec del_vertex(graffeo:graph(), graffeo:vertex()) -> ok.
del_vertex(G, V) ->
    D = require_handle(del_vertex, G),
    digraph:del_vertex(D, V),
    ok.

-doc """
Remove the `From→To` edge.

If the underlying digraph has parallel edges (e.g. from `wrap/1`),
all of them are removed (simple-graph contract).
""".
-spec del_edge(graffeo:graph(), graffeo:vertex(), graffeo:vertex()) -> ok.
del_edge(G, From, To) ->
    D = require_handle(del_edge, G),
    remove_edges(D, From, To),
    ok.

-doc "Delete a list of vertices and their incident edges.".
-spec del_vertices(graffeo:graph(), [graffeo:vertex()]) -> ok.
del_vertices(G, Vs) ->
    D = require_handle(del_vertices, G),
    lists:foreach(fun(V) -> digraph:del_vertex(D, V) end, Vs),
    ok.

-doc "Delete a list of `{From, To}` edges.".
-spec del_edges(graffeo:graph(), [{graffeo:vertex(), graffeo:vertex()}]) -> ok.
del_edges(G, Pairs) ->
    D = require_handle(del_edges, G),
    lists:foreach(fun({From, To}) -> remove_edges(D, From, To) end, Pairs),
    ok.

%%% === graffeo_backend callbacks (bare-ref) ===

-doc "All vertices in the graph.".
-spec vertices(digraph:graph()) -> [graffeo:vertex()].
vertices(Ref) ->
    digraph:vertices(Ref).

-doc "Vertices reachable from `V` via outgoing edges (deduplicated).".
-spec out_neighbours(digraph:graph(), graffeo:vertex()) -> [graffeo:vertex()].
out_neighbours(Ref, V) ->
    lists:uniq(digraph:out_neighbours(Ref, V)).

-doc "Vertices that reach `V` via incoming edges (deduplicated).".
-spec in_neighbours(digraph:graph(), graffeo:vertex()) -> [graffeo:vertex()].
in_neighbours(Ref, V) ->
    lists:uniq(digraph:in_neighbours(Ref, V)).

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

%%% === Extra accessors (bare-ref) ===

-doc """
Get edge metadata between two vertices.

If parallel edges exist (only possible via `wrap/1` of an external
multigraph), returns the metadata of the edge with the highest edge
ID by Erlang term order. For stdlib `digraph` this is the
most-recently-added edge, matching the map backend's last-writer-wins.
The selection is deterministic and independent of traversal order.
""".
-spec edge_meta(digraph:graph(), graffeo:vertex(), graffeo:vertex()) ->
    {ok, graffeo:edge_meta()} | error.
edge_meta(Ref, From, To) ->
    Edges = digraph:out_edges(Ref, From),
    find_max_edge_meta(Ref, Edges, To).

-doc "Get the label of a vertex.".
-spec vertex_label(digraph:graph(), graffeo:vertex()) ->
    {ok, graffeo:label()} | error.
vertex_label(Ref, V) ->
    case digraph:vertex(Ref, V) of
        {V, Label} -> {ok, Label};
        false -> error
    end.

%%% === graffeo_builder callbacks (envelope-based) ===

-doc false.
-spec empty_like(graffeo:graph()) -> graffeo:graph().
empty_like(_G) ->
    new().

-doc false.
-spec build_add_vertex(graffeo:graph(), graffeo:vertex()) -> graffeo:graph().
build_add_vertex(G, V) ->
    ok = add_vertex(G, V),
    G.

-doc false.
-spec build_add_vertex(graffeo:graph(), graffeo:vertex(), graffeo:label()) -> graffeo:graph().
build_add_vertex(G, V, Label) ->
    ok = add_vertex(G, V, Label),
    G.

-doc false.
-spec build_add_edge(graffeo:graph(), graffeo:vertex(), graffeo:vertex(), graffeo:edge_meta()) ->
    graffeo:graph().
build_add_edge(G, From, To, Meta) ->
    ok = add_edge(G, From, To, Meta),
    G.

%%% --- Internal ---

-spec require_handle(atom(), graffeo:graph()) -> digraph:graph().
require_handle(_Op, #graffeo{backend = ?MODULE, ref = D}) ->
    D;
require_handle(Op, #graffeo{backend = Backend}) ->
    erlang:error({handle_only, Op, Backend}).

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

-spec find_max_edge_meta(digraph:graph(), [digraph:edge()], graffeo:vertex()) ->
    {ok, graffeo:edge_meta()} | error.
find_max_edge_meta(Ref, Edges, To) ->
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
            {_, Meta} = lists:max(Matching),
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
