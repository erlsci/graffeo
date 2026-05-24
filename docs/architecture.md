# graffeo — Architecture

This document describes how graffeo is put together: the design commitments, the
opaque graph value, the behaviours that form its spine, the storage backends, where
the algorithms live, the data model, and the invariants the test suite enforces.

## Two commitments

graffeo rests on two design choices, and almost every structural decision follows
from one of them.

**One algorithm layer, many backends.** Erlang's standard-library graph algorithms
were written functional-first: they touch storage only through a thin set of *read*
accessors and never mutate the graph they traverse. graffeo makes that implicit seam
explicit as an Erlang *behaviour*, so each algorithm is written once and runs over
any backend that satisfies the contract — the same property Rust's `petgraph` gets
from its graph traits, expressed the Erlang way.

**Two tiers, faithful to Erlang.** The standard library splits the world into
*values* (`lists`, `maps`, `sets`) and *handles* (`ets`, `dets`, `digraph`). graffeo
honours that split rather than hiding it: an immutable, map-backed value tier (the
default), and a mutable, ETS/DETS-backed handle tier. Algorithms are shared across
both, because *reading* a graph is the same whether it is a value or a handle; the
tiers diverge only where it genuinely matters — in how you build and change a graph.

A third commitment is a constraint, not a structure: graffeo **embraces `digraph`
and `digraph_utils` wholesale**. Every ported function keeps the stdlib's exact name,
arity, argument order, return shape, and semantics. graffeo only adds; it never
redefines what the standard library already settled.

## The opaque graph value and the façade

A graffeo graph is an opaque value — an envelope that pairs a **backend module** with
that backend's **reference**:

```erlang
#graffeo{backend = Module, ref = Ref}
```

The `graffeo` module is the public façade and the universal algorithm layer. Every
`graffeo:*` call destructures the envelope and dispatches to the backend behaviour:

```erlang
topsort(#graffeo{backend = B, ref = R}) -> graffeo_conn:topsort(B, R, ...).
```

Because the envelope carries its own backend identity, callers never name a backend
when running algorithms — `graffeo:dijkstra/2` works identically whether the graph is
a map value or an ETS handle. The façade exposes `wrap_ref/2`, `extract_ref/2`, and
`backend/1` for the backends and constructive algorithms to (un)wrap envelopes; user
code does not need them.

## The behaviours: a read half and a build half

The seam is split into two behaviours, because reading and building have different
audiences.

**`graffeo_backend` — the read half.** The universal accessors every algorithm
consumes, semantically identical across all backends:

`vertices/1`, `out_neighbours/2`, `in_neighbours/2`, `in_degree/2`, `out_degree/2`,
`no_edges/1`, `no_vertices/1`, `edge_meta/3`, `vertex_label/2`.

Every algorithm in graffeo is written against *these nine callbacks and nothing
else*. The DFS/forest engine that powers the `digraph_utils` family contains no
literal `digraph:` calls — it runs purely over the read half, which is what makes
"one algorithm body, many backends" real rather than aspirational.

**`graffeo_builder` — the build half.** What a *constructive* algorithm needs to
produce a result graph of the same backend as its input, without naming that backend:

`empty_like/1` (a fresh empty graph of the same backend), `build_add_vertex/2,3`,
`build_add_edge/4`.

The split is deliberate: a read-only consumer should not be forced to implement
construction, and constructive algorithms (`subgraph`, `condensation`, `filter_edges`,
`contract`) need only `empty_like` + the envelope `build_add_*` to be
backend-agnostic.

## The backends

The backend axis is *storage substrate*, mirroring Erlang's own value/handle split:

| Module | Tier | Substrate | Nature |
|--------|------|-----------|--------|
| `graffeo_map` | value | a pair of maps | immutable; ops return a new graph; copyable, pattern-matchable, message-passable |
| `graffeo_ets` | handle | ETS (via stdlib `digraph`) | mutable, process-owned; ops mutate in place and return `ok` |
| `graffeo_dets` | handle | DETS (on disk) | *roadmap* — persistent, on-disk |

**`graffeo_map`** stores **dual adjacency** — an out-map and an in-map — so
`in_neighbours/2` and `in_degree/2` are O(degree) rather than requiring a full scan.
That made first-class reverse traversal free to add. Every operation returns a new
value; the original is untouched.

**`graffeo_ets`** is a thin wrapper over the stdlib `digraph` module (which is itself
ETS-backed and process-owned). It is named for its *substrate*, not its
implementation: `graffeo_map`/`graffeo_ets`/`graffeo_dets` name the storage tier,
the way Erlang's own `maps`/`ets`/`dets` do. The wrapper is a feature, not a
shortcut — `wrap/1` lifts a bare `digraph:graph()` into the envelope so the algorithm
layer works on a handle you already have, and `unwrap/1` returns the bare handle for
raw `digraph:*` access. Lifecycle (`new/0`, `delete/1`) stays in graffeo's namespace.

## Where the algorithms live

The façade is the front door; the algorithms live behind it in domain modules, each
written against the read half:

- **`graffeo_path`** — weighted shortest paths: `dijkstra/2,3`, `astar/3,4` (pluggable
  cost function; admissible heuristic that degenerates to Dijkstra).
- **`graffeo_conn`** — connectivity and construction: `components`, `strong_components`,
  `cyclic_strong_components`, `reachable`/`reaching` (+ `_neighbours`), `is_acyclic`,
  `is_tree`, `is_arborescence`, `arborescence_root`, `loop_vertices`,
  `preorder`/`postorder`; the constructive `subgraph/2,3`, `condensation/1`,
  `filter_edges/2`, and `contract/2,3`.
- **`graffeo_traverse`** — `bfs/2,3` (direction `out`/`in`/`both`, an edge filter, and
  distances), `degree`, `degree_centrality`, `top_k_by_degree`.

There is no `graffeo_utils` junk drawer; new algorithm families slot in as new domain
modules fronted by the same façade.

## The data model

**Simple directed graphs.** graffeo models *simple* directed graphs: at most one edge
per ordered `(From, To)` pair. Edge identity *is* the ordered pair — `edge_meta/3` is
keyed by it, and `add_edge` on an existing pair replaces. The handle backend
normalises away any parallel edges a bare `digraph` might carry, so the simple-graph
contract holds uniformly across tiers. (Multi-edge support is a roadmap item, not a
silent capability.)

**Vertices are any term.** A vertex is an arbitrary Erlang term — an atom, a binary, a
tuple. This is load-bearing: it lets a consumer model layered graphs (e.g. a
`{Source, Slug}` tuple for one layer and a bare `Slug` for another) without any
special support, and it is what makes `contract/2` a general quotient rather than a
fixed operation.

**Edge metadata.** Each edge carries `#{weight => number(), label => term()}`.
`weight` feeds the shortest-path cost functions (whose defaults read it); `label` is
arbitrary consumer data. Edge type, provenance, and any other per-edge attribute live
in `label` — graffeo stays agnostic to its contents, which is why `filter_edges` and
`contract` take predicates and merge functions rather than knowing about types.

## Invariants, and how they are enforced

Two parity invariants define "correct" in graffeo, and the test suite enforces both
rather than asserting them:

1. **Cross-tier parity.** The same algorithm over the same edge set returns identical
   results on a `graffeo_map` value and a `graffeo_ets` handle. This is the proof that
   the read-half seam is real.
2. **Stdlib parity.** On the handle backend, every *ported* function returns exactly
   what its `digraph`/`digraph_utils` counterpart returns on the same underlying
   handle — the faithful-port proof. (One documented exception: `get_short_path/3`
   guarantees shortest length, a valid path, correct endpoints, and reachability
   agreement, but may select a different equally-short path than `digraph` when
   several exist.)

PropEr properties generalise both over random graphs. Construction is deterministic
where it must be (canonical ordering), so a graph built twice from the same input is
structurally identical — the precondition for replaying a build across backends.

graffeo-native additions follow graffeo's tagged conventions (`{ok, _}` / `{error, _}`,
or `none` for "no result"); ported functions keep the stdlib's own shapes
(`false`/`[]`). Errors are validated at the edge and crash in the interior; Tier-1
operations on a handle, or handle-only operations on a value, raise clear tagged
errors (`{tier1_only, Op, Backend}`, `{handle_only, Op, Backend}`) rather than
returning nonsense.

## Tier-2 lifecycle

The value/handle distinction surfaces exactly where construction happens. A
constructive algorithm (`subgraph`, `condensation`, `filter_edges`, `contract`) over a
*value* returns a new value. Over a *handle* it returns a **new, owned `graffeo_ets`
handle** the caller is responsible for releasing with `graffeo_ets:delete/1` — the
same discipline as the stdlib's own handle types.

## Performance notes

The behaviour seam costs one dynamic (behaviour) dispatch per read accessor — most
visibly, per neighbour lookup in a hot traversal loop. It is the one performance cost
worth watching, and it is measurable rather than speculative: on very large graphs in
tight loops, the indirection is the thing to profile first.

## Roadmap

On the way: an edge-induced subgraph (`filter_edges/2`) and vertex contraction
(`contract/2,3`) — landing now; then minimum spanning trees, negative-weight shortest
paths (Bellman-Ford), the `graffeo_dets` on-disk backend, and multi-edge support.
Expect the public API to keep moving until 1.0. Milestone-level design thinking lives
under [`docs/design/`](docs/design/).
