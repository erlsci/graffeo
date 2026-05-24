-module(graffeo_mnesia).
-moduledoc """
Mnesia-backed, transactional / replicated handle backend.

The fourth graffeo backend. Its reason to exist is **atomic
multi-mutation transactions** and **multi-node replicated graphs**
— not raw speed (every Mnesia write costs an ETS write plus
overhead; prefer `graffeo_ets` for non-persistent, non-transactional
use — PF-12).

Each graph is a set of three named Mnesia tables (vtab/etab/ntab)
within the node-global Mnesia instance. Reads are dirty by default
(fast, lock-free); inside a `transaction/1` they use locked reads
for a consistent snapshot.

Distributed Mnesia is available via the `nodes`/`majority` options
in `open/2`; its partition behaviour is Mnesia's own — use knowingly
(DIST-14).

Constructive ops (`subgraph`, `condensation`, `filter_edges`,
`contract`) are not supported over Mnesia — use `graffeo:copy/2`
to materialise an in-memory result into a Mnesia graph.
""".

-behaviour(graffeo_backend).
-behaviour(graffeo_builder).

-export([
    new/0,
    open/1, open/2,
    close/1,
    delete/1,
    transaction/1
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

-record(graffeo_vtab, {v, label}).
-record(graffeo_etab, {pair, meta}).
-record(graffeo_ntab, {key, target}).

-record(mnesia_ref, {
    vtab :: atom(),
    etab :: atom(),
    ntab :: atom()
}).

-doc "Opaque reference to the Mnesia-backed graph tables.".
-opaque ref() :: #mnesia_ref{}.
-export_type([ref/0]).

%%% === Lifecycle ===

-doc "Create a new ephemeral Mnesia graph (ram_copies).".
-spec new() -> graffeo:graph().
new() ->
    ensure_mnesia(),
    Name = "tmp_" ++ integer_to_list(erlang:unique_integer([positive])),
    create_tables(Name, #{storage => ram_copies}).

-doc "Open or create a persistent named Mnesia graph (disc_copies).".
-spec open(string() | binary()) -> graffeo:graph().
open(Name) ->
    open(Name, #{}).

-doc """
Open or create a named Mnesia graph with options.

Options:
- `storage`: `ram_copies` | `disc_copies` | `disc_only_copies`
  (default `disc_copies`).
- `nodes`: list of nodes for replication (default `[node()]`).
- `majority`: boolean (default `false`).
""".
-spec open(string() | binary(), map()) -> graffeo:graph().
open(Name, Opts) when is_binary(Name) ->
    open(binary_to_list(Name), Opts);
open(Name, Opts) when is_list(Name) ->
    ensure_mnesia(),
    create_tables(Name, Opts).

-doc "Release the graph handle (Mnesia keeps disc tables).".
-spec close(graffeo:graph()) -> ok.
close(G) ->
    _ = require_handle(close, G),
    ok.

-doc "Delete the graph's Mnesia tables.".
-spec delete(graffeo:graph()) -> ok.
delete(G) ->
    Ref = require_handle(delete, G),
    {atomic, ok} = mnesia:delete_table(Ref#mnesia_ref.vtab),
    {atomic, ok} = mnesia:delete_table(Ref#mnesia_ref.etab),
    {atomic, ok} = mnesia:delete_table(Ref#mnesia_ref.ntab),
    ok.

-doc """
Run a function inside a Mnesia transaction.

Read and write operations on the graph automatically dispatch to
locked Mnesia operations when called inside a transaction, giving
atomic mutations and consistent-snapshot reads.
""".
-spec transaction(fun(() -> T)) -> {atomic, T} | {aborted, term()}.
transaction(Fun) ->
    mnesia:transaction(Fun).

%%% === Mutation ===

-doc "Add a vertex with the default label.".
-spec add_vertex(graffeo:graph(), graffeo:vertex()) -> ok.
add_vertex(G, V) ->
    add_vertex(G, V, undefined).

-doc "Add a vertex with a label.".
-spec add_vertex(graffeo:graph(), graffeo:vertex(), graffeo:label()) -> ok.
add_vertex(G, V, Label) ->
    Ref = require_handle(add_vertex, G),
    write(Ref#mnesia_ref.vtab, #graffeo_vtab{v = V, label = Label}),
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
    ensure_vertex_raw(Ref, From),
    ensure_vertex_raw(Ref, To),
    case read(Ref#mnesia_ref.etab, {From, To}) of
        [] ->
            write(
                Ref#mnesia_ref.ntab,
                #graffeo_ntab{key = {out, From}, target = To}
            ),
            write(
                Ref#mnesia_ref.ntab,
                #graffeo_ntab{key = {in, To}, target = From}
            );
        _ ->
            ok
    end,
    write(
        Ref#mnesia_ref.etab,
        #graffeo_etab{pair = {From, To}, meta = Meta}
    ),
    ok.

-doc "Remove vertex `V` and all its incident edges.".
-spec del_vertex(graffeo:graph(), graffeo:vertex()) -> ok.
del_vertex(G, V) ->
    Ref = require_handle(del_vertex, G),
    OutNbrs = out_neighbours_raw(Ref, V),
    InNbrs = in_neighbours_raw(Ref, V),
    lists:foreach(fun(To) -> del_edge_raw(Ref, V, To) end, OutNbrs),
    lists:foreach(fun(From) -> del_edge_raw(Ref, From, V) end, InNbrs),
    delete_record(Ref#mnesia_ref.vtab, V),
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
    Keys = dirty_all_keys(Ref#mnesia_ref.vtab),
    Keys.

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
    table_size(Ref#mnesia_ref.etab).

-doc "Total number of vertices.".
-spec no_vertices(ref()) -> non_neg_integer().
no_vertices(Ref) ->
    table_size(Ref#mnesia_ref.vtab).

-doc "Get edge metadata.".
-spec edge_meta(ref(), graffeo:vertex(), graffeo:vertex()) ->
    {ok, graffeo:edge_meta()} | error.
edge_meta(Ref, From, To) ->
    case read(Ref#mnesia_ref.etab, {From, To}) of
        [#graffeo_etab{meta = Meta}] -> {ok, Meta};
        [] -> error
    end.

-doc "Get the label of a vertex.".
-spec vertex_label(ref(), graffeo:vertex()) ->
    {ok, graffeo:label()} | error.
vertex_label(Ref, V) ->
    case read(Ref#mnesia_ref.vtab, V) of
        [#graffeo_vtab{label = Label}] -> {ok, Label};
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

%%% === Internal: bootstrap ===

-spec ensure_mnesia() -> ok.
ensure_mnesia() ->
    case mnesia:system_info(is_running) of
        yes ->
            ok;
        _ ->
            MnesiaDir = filename:join(graffeo_config:data_dir(), "mnesia"),
            ok = filelib:ensure_dir(filename:join(MnesiaDir, "probe")),
            application:set_env(mnesia, dir, MnesiaDir),
            case mnesia:create_schema([node()]) of
                ok -> ok;
                {error, {_, {already_exists, _}}} -> ok
            end,
            ok = mnesia:start()
    end.

-spec create_tables(string(), map()) -> graffeo:graph().
create_tables(Name, Opts) ->
    Storage = maps:get(storage, Opts, disc_copies),
    Nodes = maps:get(nodes, Opts, [node()]),
    Majority = maps:get(majority, Opts, false),
    VTab = table_name(Name, "vtab"),
    ETab = table_name(Name, "etab"),
    NTab = table_name(Name, "ntab"),
    ensure_table(
        VTab,
        set,
        graffeo_vtab,
        record_info(fields, graffeo_vtab),
        Storage,
        Nodes,
        Majority
    ),
    ensure_table(
        ETab,
        set,
        graffeo_etab,
        record_info(fields, graffeo_etab),
        Storage,
        Nodes,
        Majority
    ),
    ensure_table(
        NTab,
        bag,
        graffeo_ntab,
        record_info(fields, graffeo_ntab),
        Storage,
        Nodes,
        Majority
    ),
    ok = mnesia:wait_for_tables([VTab, ETab, NTab], 5000),
    Ref = #mnesia_ref{vtab = VTab, etab = ETab, ntab = NTab},
    graffeo:wrap_ref(?MODULE, Ref).

-spec ensure_table(
    atom(),
    atom(),
    atom(),
    [atom()],
    atom(),
    [node()],
    boolean()
) -> ok.
ensure_table(Tab, Type, RecName, Fields, Storage, Nodes, Majority) ->
    case
        mnesia:create_table(Tab, [
            {type, Type},
            {record_name, RecName},
            {attributes, Fields},
            {Storage, Nodes},
            {majority, Majority}
        ])
    of
        {atomic, ok} -> ok;
        {aborted, {already_exists, Tab}} -> ok
    end.

-dialyzer({no_underspecs, table_name/2}).
-spec table_name(string(), nonempty_string()) -> atom().
table_name(Name, Suffix) ->
    list_to_atom("graffeo_" ++ Name ++ "_" ++ Suffix).

%%% === Internal: dirty/txn dispatch ===

-type record() :: #graffeo_vtab{} | #graffeo_etab{} | #graffeo_ntab{}.
-type ntab_record() :: #graffeo_ntab{}.

-spec write(atom(), record()) -> ok.
write(Tab, Record) ->
    case mnesia:is_transaction() of
        true -> mnesia:write(Tab, Record, write);
        false -> mnesia:dirty_write(Tab, Record)
    end.

-spec read(atom(), term()) -> [tuple()].
read(Tab, Key) ->
    case mnesia:is_transaction() of
        true -> mnesia:read(Tab, Key);
        false -> mnesia:dirty_read(Tab, Key)
    end.

-spec delete_record(atom(), term()) -> ok.
delete_record(Tab, Key) ->
    case mnesia:is_transaction() of
        true -> mnesia:delete(Tab, Key, write);
        false -> mnesia:dirty_delete(Tab, Key)
    end.

-spec delete_object(atom(), ntab_record()) -> ok.
delete_object(Tab, Record) ->
    case mnesia:is_transaction() of
        true -> mnesia:delete_object(Tab, Record, write);
        false -> mnesia:dirty_delete_object(Tab, Record)
    end.

-spec dirty_all_keys(atom()) -> [term()].
dirty_all_keys(Tab) ->
    mnesia:dirty_all_keys(Tab).

-spec table_size(atom()) -> non_neg_integer().
table_size(Tab) ->
    mnesia:table_info(Tab, size).

%%% === Internal: helpers ===

-spec require_handle(atom(), graffeo:graph()) -> ref().
require_handle(Op, G) ->
    case graffeo:backend(G) of
        ?MODULE -> graffeo:extract_ref(?MODULE, G);
        Other -> erlang:error({handle_only, Op, Other})
    end.

-spec ensure_vertex_raw(ref(), graffeo:vertex()) -> ok.
ensure_vertex_raw(Ref, V) ->
    case read(Ref#mnesia_ref.vtab, V) of
        [] ->
            write(
                Ref#mnesia_ref.vtab,
                #graffeo_vtab{v = V, label = undefined}
            );
        _ ->
            ok
    end.

-spec out_neighbours_raw(ref(), graffeo:vertex()) -> [graffeo:vertex()].
out_neighbours_raw(Ref, V) ->
    Recs = read(Ref#mnesia_ref.ntab, {out, V}),
    [T || #graffeo_ntab{target = T} <- Recs].

-spec in_neighbours_raw(ref(), graffeo:vertex()) -> [graffeo:vertex()].
in_neighbours_raw(Ref, V) ->
    Recs = read(Ref#mnesia_ref.ntab, {in, V}),
    [T || #graffeo_ntab{target = T} <- Recs].

-spec del_edge_raw(ref(), graffeo:vertex(), graffeo:vertex()) -> ok.
del_edge_raw(Ref, From, To) ->
    delete_record(Ref#mnesia_ref.etab, {From, To}),
    delete_object(
        Ref#mnesia_ref.ntab,
        #graffeo_ntab{key = {out, From}, target = To}
    ),
    delete_object(
        Ref#mnesia_ref.ntab,
        #graffeo_ntab{key = {in, To}, target = From}
    ),
    ok.
