-module(graffeo_dets).
-moduledoc """
DETS-backed, on-disk, mutable handle backend.

The third graffeo backend — hand-rolled over three DETS tables
mirroring stdlib `digraph`'s ETS layout:

- `vtab` (set): `{V, Label}` — vertex to label.
- `etab` (set): `{{From, To}, Meta}` — edge keyed by ordered pair.
- `ntab` (bag): `{{out, V}, To}` / `{{in, V}, From}` — neighbour index.

Lifecycle:
- `new/0` — ephemeral graph under `data_dir/tmp/`; `delete/1` removes it.
- `open/1` — persistent named graph under `data_dir/`; open-or-create.
- `close/1` — flush and close, keeping the files (persistence).
- `delete/1` — close and remove the files.

The full read-half (`graffeo_backend`) is implemented, so every
`graffeo:*` algorithm works unchanged. Constructive ops
(`subgraph`, `condensation`, `filter_edges`, `contract`) are not
supported over DETS — use `graffeo:copy/2` to persist an in-memory
result to disk.
""".

-behaviour(graffeo_backend).
-behaviour(graffeo_builder).

-export([
    new/0,
    open/1,
    close/1,
    delete/1,
    from_graph/2
]).

-export([
    add_vertex/2, add_vertex/3,
    add_edge/3, add_edge/4,
    del_vertex/2,
    del_vertices/2,
    del_edge/3,
    del_edges/2
]).

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

-export([
    empty_like/1,
    build_add_vertex/2, build_add_vertex/3,
    build_add_edge/4
]).

-record(dets_ref, {
    vtab :: dets:tab_name(),
    etab :: dets:tab_name(),
    ntab :: dets:tab_name(),
    dir :: file:filename_all()
}).

-doc "Opaque reference to the DETS-backed graph internals.".
-opaque ref() :: #dets_ref{}.
-export_type([ref/0]).

%%% === Lifecycle ===

-doc "Create a new ephemeral DETS graph under `data_dir/tmp/`.".
-spec new() -> graffeo:graph().
new() ->
    TmpDir = filename:join(graffeo_config:data_dir(), "tmp"),
    Name = integer_to_list(erlang:unique_integer([positive])),
    Dir = filename:join(TmpDir, Name),
    open_tables(Dir).

-doc "Open or create a persistent named DETS graph under `data_dir/`.".
-spec open(string() | binary()) -> graffeo:graph().
open(Name) when is_binary(Name) ->
    open(binary_to_list(Name));
open(Name) when is_list(Name) ->
    Dir = filename:join(graffeo_config:data_dir(), Name),
    open_tables(Dir).

-doc "Flush and close the DETS tables, keeping the files on disk.".
-spec close(graffeo:graph()) -> ok.
close(G) ->
    Ref = require_handle(close, G),
    close_tables(Ref).

-doc "Close and remove the DETS files from disk.".
-spec delete(graffeo:graph()) -> ok.
delete(G) ->
    Ref = require_handle(delete, G),
    close_tables(Ref),
    del_dir(Ref#dets_ref.dir),
    ok.

-doc """
Build a DETS graph from any graffeo graph (convenience for `copy/2`).

Opens a persistent DETS graph at `Name` and copies all vertices and
edges from `Src` into it via `graffeo:copy/2`.
""".
-spec from_graph(graffeo:graph(), string() | binary()) -> graffeo:graph().
from_graph(Src, Name) ->
    Dst = open(Name),
    graffeo:copy(Src, Dst).

%%% === Mutation ===

-doc "Add a vertex with the default label.".
-spec add_vertex(graffeo:graph(), graffeo:vertex()) -> ok.
add_vertex(G, V) ->
    add_vertex(G, V, undefined).

-doc "Add a vertex with a label.".
-spec add_vertex(graffeo:graph(), graffeo:vertex(), graffeo:label()) -> ok.
add_vertex(G, V, Label) ->
    Ref = require_handle(add_vertex, G),
    ok = dets:insert(Ref#dets_ref.vtab, {V, Label}),
    ok.

-doc "Add an edge with default metadata.".
-spec add_edge(graffeo:graph(), graffeo:vertex(), graffeo:vertex()) -> ok.
add_edge(G, From, To) ->
    add_edge(G, From, To, #{weight => 1}).

-doc "Add an edge with metadata (last-writer-wins).".
-spec add_edge(
    graffeo:graph(),
    graffeo:vertex(),
    graffeo:vertex(),
    graffeo:edge_meta()
) -> ok.
add_edge(G, From, To, Meta) ->
    Ref = require_handle(add_edge, G),
    ensure_vertex(Ref, From),
    ensure_vertex(Ref, To),
    case dets:lookup(Ref#dets_ref.etab, {From, To}) of
        [] ->
            ok = dets:insert(Ref#dets_ref.ntab, {{out, From}, To}),
            ok = dets:insert(Ref#dets_ref.ntab, {{in, To}, From});
        _ ->
            ok
    end,
    ok = dets:insert(Ref#dets_ref.etab, {{From, To}, Meta}),
    ok.

-doc "Remove vertex `V` and all its incident edges.".
-spec del_vertex(graffeo:graph(), graffeo:vertex()) -> ok.
del_vertex(G, V) ->
    Ref = require_handle(del_vertex, G),
    OutNbrs = out_neighbours_raw(Ref, V),
    InNbrs = in_neighbours_raw(Ref, V),
    lists:foreach(fun(To) -> del_edge_raw(Ref, V, To) end, OutNbrs),
    lists:foreach(fun(From) -> del_edge_raw(Ref, From, V) end, InNbrs),
    ok = dets:delete(Ref#dets_ref.vtab, V),
    ok.

-doc "Delete a list of vertices and their incident edges.".
-spec del_vertices(graffeo:graph(), [graffeo:vertex()]) -> ok.
del_vertices(G, Vs) ->
    lists:foreach(fun(V) -> del_vertex(G, V) end, Vs),
    ok.

-doc "Remove the `From→To` edge.".
-spec del_edge(graffeo:graph(), graffeo:vertex(), graffeo:vertex()) -> ok.
del_edge(G, From, To) ->
    Ref = require_handle(del_edge, G),
    del_edge_raw(Ref, From, To),
    ok.

-doc "Delete a list of `{From, To}` edges.".
-spec del_edges(graffeo:graph(), [{graffeo:vertex(), graffeo:vertex()}]) -> ok.
del_edges(G, Pairs) ->
    Ref = require_handle(del_edges, G),
    lists:foreach(fun({From, To}) -> del_edge_raw(Ref, From, To) end, Pairs),
    ok.

%%% === graffeo_backend callbacks ===

-doc "All vertices in the graph.".
-spec vertices(ref()) -> [graffeo:vertex()].
vertices(Ref) ->
    dets:foldl(fun({V, _Label}, Acc) -> [V | Acc] end, [], Ref#dets_ref.vtab).

-doc "Outgoing neighbours of `V`.".
-spec out_neighbours(ref(), graffeo:vertex()) -> [graffeo:vertex()].
out_neighbours(Ref, V) ->
    out_neighbours_raw(Ref, V).

-doc "Incoming neighbours of `V`.".
-spec in_neighbours(ref(), graffeo:vertex()) -> [graffeo:vertex()].
in_neighbours(Ref, V) ->
    in_neighbours_raw(Ref, V).

-doc "Number of incoming edges to `V`.".
-spec in_degree(ref(), graffeo:vertex()) -> non_neg_integer().
in_degree(Ref, V) ->
    length(in_neighbours_raw(Ref, V)).

-doc "Number of outgoing edges from `V`.".
-spec out_degree(ref(), graffeo:vertex()) -> non_neg_integer().
out_degree(Ref, V) ->
    length(out_neighbours_raw(Ref, V)).

-doc "Total number of edges.".
-spec no_edges(ref()) -> non_neg_integer().
no_edges(Ref) ->
    dets:info(Ref#dets_ref.etab, no_objects).

-doc "Total number of vertices.".
-spec no_vertices(ref()) -> non_neg_integer().
no_vertices(Ref) ->
    dets:info(Ref#dets_ref.vtab, no_objects).

-doc "Get edge metadata.".
-spec edge_meta(ref(), graffeo:vertex(), graffeo:vertex()) ->
    {ok, graffeo:edge_meta()} | error.
edge_meta(Ref, From, To) ->
    case dets:lookup(Ref#dets_ref.etab, {From, To}) of
        [{{From, To}, Meta}] -> {ok, Meta};
        [] -> error
    end.

-doc "Get the label of a vertex.".
-spec vertex_label(ref(), graffeo:vertex()) ->
    {ok, graffeo:label()} | error.
vertex_label(Ref, V) ->
    case dets:lookup(Ref#dets_ref.vtab, V) of
        [{V, Label}] -> {ok, Label};
        [] -> error
    end.

%%% === graffeo_builder callbacks ===

-doc false.
-spec empty_like(graffeo:graph()) -> no_return().
empty_like(_G) ->
    erlang:error({unsupported_on_backend, empty_like, ?MODULE}).

-doc false.
-spec build_add_vertex(graffeo:graph(), graffeo:vertex()) -> graffeo:graph().
build_add_vertex(G, V) ->
    ok = add_vertex(G, V),
    G.

-doc false.
-spec build_add_vertex(graffeo:graph(), graffeo:vertex(), graffeo:label()) ->
    graffeo:graph().
build_add_vertex(G, V, Label) ->
    ok = add_vertex(G, V, Label),
    G.

-doc false.
-spec build_add_edge(
    graffeo:graph(),
    graffeo:vertex(),
    graffeo:vertex(),
    graffeo:edge_meta()
) -> graffeo:graph().
build_add_edge(G, From, To, Meta) ->
    ok = add_edge(G, From, To, Meta),
    G.

%%% === Internal ===

-spec open_tables(file:filename_all()) -> graffeo:graph().
open_tables(Dir) ->
    ok = filelib:ensure_dir(filename:join(Dir, "probe")),
    VFile = filename:join(Dir, "vtab.dets"),
    EFile = filename:join(Dir, "etab.dets"),
    NFile = filename:join(Dir, "ntab.dets"),
    VName = dets_name(VFile),
    EName = dets_name(EFile),
    NName = dets_name(NFile),
    {ok, VName} = dets:open_file(VName, [{file, VFile}, {type, set}]),
    {ok, EName} = dets:open_file(EName, [{file, EFile}, {type, set}]),
    {ok, NName} = dets:open_file(NName, [{file, NFile}, {type, bag}]),
    Ref = #dets_ref{vtab = VName, etab = EName, ntab = NName, dir = Dir},
    graffeo:wrap_ref(?MODULE, Ref).

-spec dets_name(file:filename_all()) -> atom().
dets_name(Path) ->
    list_to_atom("graffeo_dets_" ++ integer_to_list(erlang:phash2(Path))).

-spec close_tables(ref()) -> ok.
close_tables(Ref) ->
    ok = dets:close(Ref#dets_ref.vtab),
    ok = dets:close(Ref#dets_ref.etab),
    ok = dets:close(Ref#dets_ref.ntab),
    ok.

-spec del_dir(file:filename_all()) -> ok.
del_dir(Dir) ->
    case file:list_dir(Dir) of
        {ok, Files} ->
            lists:foreach(
                fun(F) -> file:delete(filename:join(Dir, F)) end, Files
            ),
            _ = file:del_dir(Dir),
            ok;
        {error, _} ->
            ok
    end.

-spec require_handle(atom(), graffeo:graph()) -> ref().
require_handle(Op, G) ->
    case graffeo:backend(G) of
        ?MODULE -> graffeo:extract_ref(?MODULE, G);
        Other -> erlang:error({handle_only, Op, Other})
    end.

-spec ensure_vertex(ref(), graffeo:vertex()) -> ok.
ensure_vertex(Ref, V) ->
    case dets:lookup(Ref#dets_ref.vtab, V) of
        [] -> ok = dets:insert(Ref#dets_ref.vtab, {V, undefined});
        _ -> ok
    end.

-spec out_neighbours_raw(ref(), graffeo:vertex()) -> [graffeo:vertex()].
out_neighbours_raw(Ref, V) ->
    [To || {{out, _}, To} <- dets:lookup(Ref#dets_ref.ntab, {out, V})].

-spec in_neighbours_raw(ref(), graffeo:vertex()) -> [graffeo:vertex()].
in_neighbours_raw(Ref, V) ->
    [From || {{in, _}, From} <- dets:lookup(Ref#dets_ref.ntab, {in, V})].

-spec del_edge_raw(ref(), graffeo:vertex(), graffeo:vertex()) -> ok.
del_edge_raw(Ref, From, To) ->
    ok = dets:delete(Ref#dets_ref.etab, {From, To}),
    ok = dets:delete_object(Ref#dets_ref.ntab, {{out, From}, To}),
    ok = dets:delete_object(Ref#dets_ref.ntab, {{in, To}, From}),
    ok.
