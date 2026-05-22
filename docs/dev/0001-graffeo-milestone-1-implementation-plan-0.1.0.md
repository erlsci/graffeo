---
title: "graffeo — Milestone 1 implementation plan (the vertical slice, 0.1.0)"
component: All
tags: [milestone, implementation-plan, ledger]
created: 2026-05-22
updated: 2026-05-22
state: Draft
---

# graffeo — Milestone 1 implementation plan (0.1.0)

*The per-milestone implementation plan (SDLC step 5) for the vertical slice
sketched at the end of the [project definition](0002-graffeo-project-definition.md).
It commits to a build order, takes positions on the open questions the
definition doc deliberately left live, discloses what M1 does **not** deliver,
and carries an acceptance ledger. Like its parent doc: committed, still meant to
be argued with.*

## What M1 proves

One claim, end to end: **the same `graffeo:*` algorithm, called the same way,
produces identical results over a Tier-1 value graph and a Tier-2 `digraph`
handle.** If that holds, the read-half behaviour is a real seam and the
universal algorithm layer is real. Everything in M1 exists to stand that claim
up and put it under test. The earns-its-place band does not open until it holds.

The slice covers R1, R2, R3, R6, R7, R8 in full; R4 as *engine + one ported
algorithm*; R5 as *Dijkstra only*. The partials are disclosed in
[§ Spec-vs-milestone disclosure](#spec-vs-milestone-disclosure), not buried.

## Decisions M1 forces (positions, open to argument)

The definition doc named five things as live. The milestone touches all of
them, so the plan has to commit. Each is a **recommendation with rationale**,
flagged for confirmation — not a settled fact.

### D0 — graffeo is a *library* application, not a running one

**Position.** Delete `graffeo_sup.erl` and `graffeo_app.erl`; remove
`{mod, {graffeo_app, []}}` from `graffeo.app.src`. Ship a library application.

**Why.** graffeo owns no long-lived process. Tier-1 graphs are values; the
algorithm layer is pure functions; a Tier-2 `digraph` graph is ETS tables owned
by the *caller's* process — `digraph:new/0` spawns nothing to supervise. The
current tree is the `rebar3 new app` default, not a design choice. A supervisor
with `intensity => 0` and no children is a tell that there is nothing to start.
(Erlang guideline PS / SUP: a library app has no `mod` entry.)

**Risk if wrong.** Near zero. If graffeo later grows a process-owning backend
(an ETS-table-server, say), the app/sup callback can be reintroduced for that
backend alone without affecting the value tier.

### D1 — two behaviours (read half + build half), not one with two groups

**Position.** `graffeo_backend` declares the **read** callbacks; a separate
`graffeo_builder` declares the **build** callbacks. A backend that does both
lists both `-behaviour` attributes.

**Why.** Erlang behaviours are all-or-nothing: a module either satisfies every
`-callback` or earns a warning. "Two callback groups in one behaviour" has no
idiomatic expression — two behaviours *is* the language's way of saying "you may
implement reads without builds." It matches the definition doc's own lean (a
read-only backend should not be forced to build), and the constructive stdlib
algorithms slated for later (`subgraph/3`, `condensation/1`) will depend only on
`graffeo_builder`, so the split pays off the first time a read-only backend or a
constructive algorithm appears. Cost today: one extra `-behaviour` line on
`graffeo_map` and `graffeo_digraph`.

**Read half (`graffeo_backend`).** `vertices/1`, `in_neighbours/2`,
`out_neighbours/2`, `in_degree/2`, `out_degree/2`, `no_edges/1`, `no_vertices/1`.
(The six from `digraph_utils` plus `out_degree/2` for the R7 degree layer.)

**Build half (`graffeo_builder`).** `new/0`, `add_vertex/2`, `add_vertex/3`
(with label), `add_edge/3`, `add_edge/4` (with weight/meta), and the
"empty graph of my own kind" constructor the constructive algorithms need.

### D2 — a uniform `#graffeo{}` envelope carries backend identity

**Position.** The opaque public graph value is a thin record
`#graffeo{backend :: module(), ref :: term()}`. `graffeo:new/0` returns
`#graffeo{backend = graffeo_map, ref = MapValue}`. `graffeo_digraph:new/0`
returns `#graffeo{backend = graffeo_digraph, ref = DigraphHandle}`, and
`graffeo_digraph:wrap/1` lifts an existing bare `digraph` handle into the
envelope. The façade dispatches with one line:
`Backend = G#graffeo.backend, Backend:out_neighbours(G#graffeo.ref, V)`.

**Why.** The definition doc commits to "the graph value carries its own backend
identity, so the façade dispatches without the user naming the backend again."
An envelope delivers exactly that and keeps dispatch trivial. The alternative —
detecting a raw `digraph` by its internal tuple shape — pattern-matches an
`-opaque` stdlib type, which is an anti-pattern and brittle across OTP versions.
`wrap/1` preserves the definition doc's transparency goal ("operate on a digraph
directly") as a one-call lift: graffeo never hides the handle's mutability, it
just labels it for dispatch. A Tier-2 user who wants no algorithm layer ignores
graffeo entirely and uses `digraph` — unchanged.

### D3 — the maps backend stores dual adjacency in a record

**Position.** `graffeo_map`'s `ref` is a record holding a vertex/label map and
**both** forward and reverse adjacency:

```erlang
-record(gmap, {
    vs  :: #{vertex() => label()},                       % vertex set + labels
    out :: #{vertex() => #{vertex() => edge_meta()}},    % forward adjacency
    in  :: #{vertex() => #{vertex() => edge_meta()}}      % reverse adjacency
}).
```

**Why.** R8 makes reverse traversal a first-class peer of forward traversal;
storing reverse adjacency explicitly makes `in_neighbours/2` and `in_degree/2`
O(degree) instead of an O(edges) scan. Inner *maps* of neighbours (not lists)
give O(1) edge existence, dedup, and per-edge `edge_meta` (weight + label) in one
place. This is the representation that keeps the read half — the contract every
algorithm leans on — uniformly cheap. Lowest-stakes of the five decisions; it is
backend-private and can change without touching the façade or any algorithm.

### D4 — Dijkstra takes a cost function with a sensible default

**Position.** `graffeo:dijkstra(G, Source)` uses the stored numeric edge weight
as cost. `graffeo:dijkstra(G, Source, #{cost => fun((edge_meta()) -> number())})`
supplies a custom cost — covering fabryk's inverted-weight trick
(`cost = 1 / max(W, Eps)`) and edge-type-derived costs.

**Why.** The definition doc judged the function form "the right general
primitive," and fabryk's real usage needed it. The default makes the common case
(stored weight) zero-ceremony; the function covers the general case without a
second API. This is "both" in practice — a default-valued function parameter,
not two functions. Costs must be non-negative (Dijkstra's precondition); the
plan documents that and leaves negative-weight handling to a future Bellman-Ford
in the later band.

## Build order

Strictly dependency-ordered. Each step is a vertical sliver: types + impl +
specs + tests before moving on. Steps map to the definition doc's 7-point sketch
(noted as `[sketch N]`).

**S0 — Scaffolding (D0) + toolchain + core types.**
Convert to a library app (D0). Wire `rebar.config` for the house toolchain:
`dialyzer` + `xref`, `elvis` + `erlfmt`, `eunit` + `common_test` + PropEr,
coverage. Define the shared types in `graffeo.hrl` / a types module:
`vertex()`, `label()`, `weight()`, `edge_meta()`, the `#graffeo{}` envelope (D2),
and the `-opaque graph()` exported by the façade.
*Depends on: nothing.*

**S1 — Behaviours (D1).** `[sketch 1]`
Write `graffeo_backend` (read callbacks) and `graffeo_builder` (build callbacks)
with `-callback` specs and `-moduledoc`. No implementation yet — the contract
first.
*Depends on: S0.*

**S2 — `graffeo_map`, the Tier-1 value backend (D3).** `[sketch 2]`
Implement both behaviours over the `#gmap{}` record. Functional builder
(`new/0`, `add_vertex/2,3`, `add_edge/3,4`) — every op returns a new graph,
original untouched. Labels on vertices, weight/meta on edges. Read accessors over
dual adjacency.
*Depends on: S1.*

**S3 — `graffeo_map` constructors land on the façade.**
`graffeo:new/0` and the Tier-1 builder surface, wrapping into `#graffeo{}` (D2).
This is the "blessed front door."
*Depends on: S2.*

**S4 — `graffeo_digraph`, the Tier-2 handle backend (D2).** `[sketch 3]`
Implement the read half by delegating to `digraph` / `digraph_utils`; a minimal
build surface (`new/0`, `wrap/1`, `add_vertex`, `add_edge`) delegating straight
to `digraph`. **Not** a full mirror of `digraph`'s mutation API in M1 — see the
disclosure below.
*Depends on: S1.*

**S5 — Façade dispatch + the generic DFS engine + topsort (R4).** `[sketch 4]`
`graffeo`'s dispatch helper (D2). Port `digraph_utils`' forest/postorder engine
to run over the **read half** (this is the keystone of R4 — the engine, not just
the algorithm), then `graffeo:topsort/1` on top. Recommend **topsort** over SCC
for the first port: it is the simpler, directly evidence-backed member
(fabryk's `learning_path`), and it exercises the postorder engine the rest of the
family reuses.
*Depends on: S3, S4.*

**S6 — Dijkstra (R5, D4).** `[sketch 5]`
`graffeo_path:dijkstra/2,3` over the read half, cost-function-with-default.
*Depends on: S3, S4.*

**S7 — Directional, filterable BFS (R6) + degree metrics (R7, R8).** `[sketch 6]`
`graffeo_traverse`: BFS taking a direction (`out` / `in` / `both`) and an
edge-type filter predicate, yielding nodes with distances; `in`/`out`/total
degree, normalised degree centrality, top-k by degree. Reverse traversal (R8)
falls out of `direction => in` reusing the reverse adjacency (D3).
*Depends on: S3, S4.*

**S8 — The cross-tier proof (the acceptance gate).** `[sketch 7]`
A shared suite that builds a value graph and a handle graph **from the same edge
list** and asserts `topsort`, `dijkstra`, `bfs`, and the degree metrics return
identical results on both. Plus at least one **PropEr** property: a random edge
list → both backends → read-half parity and algorithm parity. The property test
is the strongest available evidence that the seam is real, not a hand-picked
example.
*Depends on: S5, S6, S7.*

## Spec-vs-milestone disclosure

What the slice does **not** deliver, named so it cannot drift into an implied
"done":

- **R4 is partial by design.** M1 ports the DFS engine + `topsort` only. The
  rest of the family (components, strong components, reachability/reaching,
  acyclicity, pre/postorder, tree/arborescence) is **deferred** to the
  earns-its-place band. *Re-entry:* each lands as a thin function over the engine
  S5 builds. This is the definition doc's own risk-mitigation ("port at least one
  non-trivial member early") taken literally.
- **R5 is Dijkstra-only.** A\* is **deferred**. *Re-entry:* A\* is a small
  addition once the Dijkstra skeleton + cost function (D4) exist — it needs an
  admissible-heuristic parameter, designed in a follow-on.
- **Tier-2 surface is minimal (D2/decision in definition doc OQ2).** M1 wraps
  construction + reads, not `digraph`'s full mutation API. *Re-entry:* decide
  thin-mirror-vs-transparent when more of Tier 2 is exercised.
- **`graffeo_dets`, MST, cycle enumeration, union-find WCC, all-simple-paths,
  everything in the "later" band** — out. Not started, not implied.
- **The `graffeo_builder` constructive consumers** (`subgraph/3`,
  `condensation/1`) — out; the behaviour exists in S1 but M1 ships no algorithm
  that consumes the build half beyond the backends' own constructors.

## Acceptance ledger

Per `LEDGER_DISCIPLINE.md`. Every row reaches a final status
(`done` / `deferred` / `no-op`) before M1 advances; `done` requires a commit SHA
plus Verify output. Verify commands run against the local Erlang/OTP 27 +
rebar3 toolchain (the sandbox used for planning has no `erl`; CDC runs these on
the dev machine). CC implements and self-assesses; CDC verifies independently.

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| F-0  | Library app: no `graffeo_sup`/`graffeo_app`, no `{mod,…}` in app.src | `! test -f src/graffeo_sup.erl && ! grep -q '{mod,' src/graffeo.app.src` ; `rebar3 compile` clean | serious | D0 | open | | |
| F-1  | `graffeo_backend` declares the 7 read callbacks | `grep -c '^-callback' src/graffeo_backend.erl` ≥ 7 ; `rebar3 xref` clean | serious | R1/D1 | open | | |
| F-2  | `graffeo_builder` declares the build callbacks | `grep -c '^-callback' src/graffeo_builder.erl` ≥ 5 | serious | R1/D1 | open | | |
| F-3  | `graffeo_map` is immutable: op returns new graph, original unchanged | eunit `map_immutability_test` | serious | R2 | open | | |
| F-4  | `graffeo_map` stores labels + edge weights; round-trip | eunit `map_label_weight_roundtrip_test` | correctness | R2 | open | | |
| F-5  | `graffeo_map` reverse adjacency: `in_neighbours/in_degree` correct | eunit `map_reverse_adjacency_test` | correctness | R2/R8/D3 | open | | |
| F-6  | `graffeo_digraph` read half == `digraph_utils` on same graph | eunit `digraph_read_parity_test` | serious | R3 | open | | |
| F-7  | `graffeo_digraph:wrap/1` lifts a bare handle into `#graffeo{}` | eunit `digraph_wrap_test` | correctness | R3/D2 | open | | |
| F-8  | DFS/postorder engine runs over the read half (no `digraph:` literals in engine) | `! grep -q 'digraph:' src/graffeo_conn.erl` ; eunit engine test | serious | R4 | open | | |
| F-9  | `graffeo:topsort/1` correct on a DAG; `false` on a cycle | eunit `topsort_test` | serious | R4 | open | | |
| F-10 | `graffeo:dijkstra/2` correct distances on a known weighted graph | eunit `dijkstra_default_cost_test` | serious | R5 | open | | |
| F-11 | `graffeo:dijkstra/3` honours a custom cost fun (inverted-weight) | eunit `dijkstra_custom_cost_test` | correctness | R5/D4 | open | | |
| F-12 | Directional BFS (`out`/`in`/`both`) + edge-type filter, with distances | eunit `bfs_direction_filter_test` | correctness | R6 | open | | |
| F-13 | Degree metrics: in/out/total, normalised centrality, top-k | eunit `degree_centrality_test` | correctness | R7 | open | | |
| F-14 | Reverse traversal first-class (`direction => in` dependents query) | eunit `reverse_traversal_test` | correctness | R8 | open | | |
| F-15 | **Cross-tier parity**: same suite, same edge list, identical results on value + handle graphs | ct `cross_tier_SUITE` all algorithms | serious | sketch 7 | open | | The acceptance gate. |
| F-16 | PropEr parity property: random edge list → read-half + algorithm parity across backends | `rebar3 proper -m prop_backend_parity` | serious | sketch 7 | open | | |
| F-17 | Every exported function has a `-spec`; dialyzer clean | `rebar3 dialyzer` no warnings | serious | erlang-guidelines | open | | |
| F-18 | Test coverage ≥ 90% (M1 floor; intent 95% as in textrynum) | `rebar3 cover` ≥ 90 | polish | coverage discipline | open | | Threshold open — see note. |
| F-19 | `elvis` + `erlfmt` clean | `rebar3 lint` ; `rebar3 fmt --check` | polish | tooling | open | | |
| F-20 | `-moduledoc`/`-doc` on public modules + exported functions (OTP-27) | `grep -L '\-moduledoc' src/graffeo*.erl` empty ; `rebar3 ex_doc` builds | polish | DC | open | | |

## What Worked

_(Filled in at M1 close. Patterns/decisions that made the milestone close
cleanly and should be preserved.)_

## Closure

_(Filled in at M1 close.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 21. Done: _ . Deferred: _ . No-op: _ .

---

*Status: pre-implementation plan, draft for review. Positions D0–D4 are
recommendations open to argument; the ledger is the contract once they settle.*
