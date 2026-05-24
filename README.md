# graffeo

[![Build Status][gh-actions-badge]][gh-actions]
[![Coverage][coverage-badge]][project]
[![][tag-badge]][tag]

[![Project Logo][logo]][logo-large]

*An Erlang graph library — `digraph` and then some*

graffeo wraps Erlang's two stdlib graph modules, `digraph` and `digraph_utils`,
and carries them the rest of the way toward "batteries included." Where the
stdlib stops — topological sort, components, reachability, a handful of
connectivity predicates — graffeo continues: weighted shortest paths,
composable traversal, richer connectivity, and the assorted algorithms one ends
up hand-rolling on real graph projects. The benchmark it measures itself
against is Rust's [petgraph](https://docs.rs/petgraph), which set the recent bar
for what a graph library should give you out of the box.

## About

graffeo is, in large part, a wrapper around Erlang's two standard-library graph
modules, `digraph` and `digraph_utils` — bringing them together behind a single
module so that graph-theoretic programming in Erlang has one obvious front door.

It **embraces `digraph` and `digraph_utils` wholesale.** graffeo does not redesign
or reinterpret them: every ported function keeps the stdlib's exact name, arity,
argument order, return shape, and semantics, so a `digraph` user is immediately at
home. graffeo only *adds* — it never changes what the standard library already got
right.

Structurally, it adds a thin seam and a choice of storage. A graph-access
*behaviour* lets each algorithm be written once and run over any conforming
**backend**: the immutable, map-backed *value* backend `graffeo_map` (copyable,
pattern-matchable, message-passable); an ETS-backed, process-owned *handle* backend
`graffeo_ets` (mutable, implemented over the stdlib `digraph`); and a persistent,
DETS-backed *handle* backend `graffeo_dets` (on disk, survives restarts); and a
transactional, replicated *handle* backend `graffeo_mnesia` (Mnesia-backed — atomic
multi-mutation and multi-node graphs). The design rationale lives in
[`docs/architecture.md`](docs/architecture.md).

And it adds the graph-theoretic functions you end up hand-rolling on real projects —
the ones neither `digraph` nor `digraph_utils` provide:

| Function | What it adds |
|----------|--------------|
| `dijkstra/2,3` | Weighted shortest paths (Dijkstra), with a pluggable cost function |
| `astar/3,4` | Weighted shortest paths (A\*), with a pluggable cost and an admissible heuristic |
| `bfs/2,3` | Breadth-first traversal with direction (`out`/`in`/`both`), an edge filter, and distances |
| `degree/2` | Combined in+out degree (the stdlib exposes only `in_degree`/`out_degree`) |
| `degree_centrality/2` | Normalised degree centrality |
| `top_k_by_degree/2` | The *k* most-connected vertices |
| `source_vertices/1` | Vertices with no incoming edges |
| `sink_vertices/1` | Vertices with no outgoing edges |

graffeo also carries the *entire* `digraph` / `digraph_utils` surface — topological
sort, (strongly) connected components, reachability, path and cycle queries, `subgraph`
and `condensation` — over all four backends, each checked for **exact parity** with its
stdlib counterpart *and* **cross-tier parity** between backends. "One algorithm layer,
many backends" is enforced, not merely asserted.

On the roadmap: minimum spanning trees, negative-weight shortest paths (Bellman-Ford),
and multi-edge support — graffeo currently models *simple* directed graphs (at most one
edge per ordered pair).

## Usage

Both tiers share one algorithm layer: you build a graph one of two ways, then
call the same `graffeo:*` functions over it.

### Functional tier (map-backed value, the default)

```erlang
%% Every build step returns a NEW graph; the original is untouched.
G0 = graffeo:new(),
G1 = graffeo:add_edge(G0, a, b, #{weight => 1}),
G2 = graffeo:add_edge(G1, b, c, #{weight => 2}),
G3 = graffeo:add_edge(G2, a, c, #{weight => 10}),
G  = graffeo:add_edge(G3, c, d, #{weight => 3}),

{ok, _Order}   = graffeo:topsort(G),       %% a valid topological order, e.g. [a, b, c, d]
{Dist, _Prev}  = graffeo:dijkstra(G, a),   %% #{a => 0, b => 1, c => 3, d => 6}
{ok, _Path, 6} = graffeo:astar(G, a, d),   %% weighted A*: cheapest a→d is a,b,c,d (6), not a,c,d (13)
3              = graffeo:degree(G, c),      %% in: a, b (2) + out: d (1)
[a, b, c, d]   = lists:sort(graffeo:reachable(G, [a])),  %% the digraph_utils family, on the same value
true           = graffeo:is_acyclic(G),
[{a, 0} | _]   = graffeo:bfs(G, a).         %% [{Vertex, Distance}], breadth-first from the source
```

Because the graph is a plain value, `G0` still has zero edges after all of the
above — nothing was mutated, and `G` can be pattern-matched or sent between
processes like any other term.

### Handle tier (`graffeo_ets` — ETS-backed, mutable)

```erlang
%% A mutable handle, ETS-backed (over stdlib digraph) and owned by your process.
%% One value, one namespace: build, run algorithms, then clean up.
G = graffeo_ets:new(),
graffeo_ets:add_edge(G, a, b, #{weight => 1}),
graffeo_ets:add_edge(G, b, c, #{weight => 2}),
graffeo_ets:add_edge(G, a, c, #{weight => 10}),
graffeo_ets:add_edge(G, c, d, #{weight => 3}),

%% The SAME graffeo:* algorithm calls — no wrapping needed.
{ok, _Order}  = graffeo:topsort(G),
{Dist, _Prev} = graffeo:dijkstra(G, a),   %% #{a => 0, b => 1, c => 3, d => 6}

graffeo_ets:delete(G).   %% lifecycle stays in graffeo's namespace
```

If you already have a bare `digraph` handle, `graffeo_ets:wrap/1` lifts it into the
envelope so the algorithm layer works on it. `unwrap/1` hands the bare handle back
when you need raw `digraph:*` access.

### Persistent tier (`graffeo_dets` — on-disk, survives restarts)

`graffeo_dets` is the same handle experience as `graffeo_ets`, backed by DETS on disk.
`new/0` gives an ephemeral graph (just like `graffeo_ets`); `open/1` gives a **named,
persistent** one that outlives the VM.

```erlang
%% Ephemeral — identical experience to graffeo_ets, just on disk.
G = graffeo_dets:new(),
graffeo_dets:add_edge(G, a, b, #{weight => 1}),
{Dist, _Prev} = graffeo:dijkstra(G, a),   %% the SAME graffeo:* algorithms
graffeo_dets:delete(G).                    %% close + remove the files
```

```erlang
%% Persistent — build once, reopen later, query without rebuilding.
G  = graffeo_dets:open(my_graph),
graffeo_dets:add_edge(G, a, b, #{weight => 1}),
graffeo_dets:add_edge(G, b, c, #{weight => 2}),
graffeo_dets:close(G),                     %% flush + keep the files on disk

%% ... a VM restart later ...
G2 = graffeo_dets:open(my_graph),          %% the data is still there
{ok, _Order} = graffeo:topsort(G2),
graffeo_dets:close(G2).
```

To persist an in-memory graph, `graffeo:copy/2` materialises any graph into an opened
backend: `graffeo:copy(MapG, graffeo_dets:open(snapshot))`.

**Where files live.** On-disk backends store under a configurable `data_dir`, resolved
as: an explicit `data_dir` in `sys.config` → `priv/data` (if writable) → a CWD-based
`graffeo_data/` → the OS cache dir. In a release `priv` is typically read-only, so
**production should set `data_dir` in `sys.config`**:

```erlang
%% sys.config
[{graffeo, [{data_dir, "/var/lib/myapp/graffeo"}]}].
```

### Transactional / replicated tier (`graffeo_mnesia`)

`graffeo_mnesia` is the same handle experience again, backed by Mnesia — reach for it
when you need **atomic multi-mutation transactions** or **multi-node replicated**
graphs (for plain persistence, `graffeo_dets` is lighter). `new/0` is ephemeral
(`ram_copies`); `open/1` is persistent (`disc_copies`).

```erlang
G = graffeo_mnesia:new(),
graffeo_mnesia:add_edge(G, a, b, #{weight => 1}),
{Dist, _Prev} = graffeo:dijkstra(G, a),   %% the SAME graffeo:* algorithms
graffeo_mnesia:delete(G).
```

Wrap a batch of mutations — or a read — in `transaction/1` for atomicity and a
consistent snapshot:

```erlang
graffeo_mnesia:transaction(fun() ->
    graffeo_mnesia:add_edge(G, a, b, #{weight => 1}),
    graffeo_mnesia:add_edge(G, b, c, #{weight => 2})
end),                                       %% atomic: both edges, or neither
{atomic, {ok, _Order}} =
    graffeo_mnesia:transaction(fun() -> graffeo:topsort(G) end).
```

Inside `transaction/1` the read and write paths automatically use locked Mnesia
operations; outside, they're dirty (fast, lock-free) — the same code, the context
decides. `open/2` takes `#{storage => disc_copies | ram_copies | disc_only_copies,
nodes => [node()], majority => boolean()}`; multi-node replication rides the `nodes`
option, but its partition behaviour is Mnesia's own — use it knowingly. Mnesia's data
directory comes from the same `data_dir` config as `graffeo_dets`.

## Build

```shell
rebar3 compile
```

## License

Apache License 2.0. See [LICENSE](LICENSE).

[//]: ---Named-Links---

[project]: https://github.com/erlsci/graffeo
[logo]: priv/images/logo.png
[logo-large]: priv/images/logo-large.png
[coverage-badge]: https://img.shields.io/badge/coverage-96%25-brightgreen
[gh-actions-badge]: https://github.com/erlsci/graffeo/workflows/ci/badge.svg
[gh-actions]: https://github.com/erlsci/graffeo/actions?query=workflow%3Aci
[tag-badge]: https://img.shields.io/github/tag/erlsci/graffeo.svg
[tag]: https://github.com/erlsci/graffeo/tags
