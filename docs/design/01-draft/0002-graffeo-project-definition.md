---
number: 2
title: "graffeo — project definition"
author: "each backend"
component: All
tags: [change-me]
created: 2026-05-22
updated: 2026-05-22
state: Draft
supersedes: null
superseded-by: null
version: 1.0
---

# graffeo — project definition

*Decision-grade follow-on to the [prospectus](0001-graffeo-project-prospectus.md).
Still meant to be argued with, but it commits where the prospectus only flagged.*

## What this document is

The prospectus laid out three open questions and named the first — the
mutable-vs-value-oriented fork — as the load-bearing decision that everything
downstream leans on. It also named the right way to find the real requirements:
inventory the algorithms already hand-rolled on top of petgraph, because those
are proof of what is actually missing rather than what a feature checklist
says should be there.

This document does both. It resolves the fork, seeds the requirements from that
inventory, and fixes a first-cut scope and module layout. It is the
project-definition step: goals, non-goals, requirements, architecture spine,
scope, and the milestone that proves it. Detailed per-algorithm design is
deferred to subsequent design docs.

## What graffeo is

An Erlang library that wraps the two stdlib digraph modules — `digraph` and
`digraph_utils` — and closes the gap to [petgraph](https://docs.rs/petgraph).
Where `digraph_utils` stops (topological sort, components, reachability, a
handful of connectivity predicates), graffeo carries the rest: weighted
shortest paths, composable traversal, the connectivity and spanning-tree
algorithms one ends up hand-rolling, and — the part that makes it *yours* —
first-class support for the domain compositions that real graph projects
actually need, several of which petgraph does not ship at all.

## The architecture spine: an access behaviour, not a backend

The prospectus framed Q1 as a three-way tie: stay faithful to mutable
`digraph`; offer a value-oriented layer; or run two faces at once. Reading the
stdlib source dissolves the tie.

`digraph_utils` is written *functional-first*. Its module header cites
Launchbury's *"Graph Algorithms with a Functional Flavour"* (1995), and the
code lives up to it. The entire depth-first family — connected components,
strong components, reachability and reaching, topological sort, acyclicity,
pre/postorder, tree and arborescence predicates — runs through one parameterised
traversal engine (`forest/4` → `pretraverse` → `ptraverse`/`posttraverse`). That
engine threads its visited-set as a **pure `sets` accumulator**, not an ETS
table. It never mutates the input graph. It reaches storage through exactly one
seam: three one-line successor functions.

```erlang
in(G, V, Vs)    -> digraph:in_neighbours(G, V) ++ Vs.
out(G, V, Vs)   -> digraph:out_neighbours(G, V) ++ Vs.
inout(G, V, Vs) -> in(G, V, out(G, V, Vs)).
```

Across the whole module the read surface is just six accessors —
`vertices/1`, `in_neighbours/2`, `out_neighbours/2`, `in_degree/2`,
`no_edges/1`, `no_vertices/1`. Every read-only algorithm bottoms out in those
and nothing else. The coupling to `digraph` is therefore *shallow and at the
wrong layer to hurt*: the accessors are hardcoded as literal `digraph:` module
calls rather than passed in, but nothing is tied to ETS, to process ownership,
or to in-place mutation. The stdlib already separated traversal from access. It
simply never exposed the seam.

**Decision.** graffeo exposes that seam as an Erlang **behaviour**,
`graffeo_backend`, split along the line the seam itself suggests:

- a **read half** — the accessors above plus `out_degree/2` for the degree
  layer — implemented by *every* backend and consumed by *every* algorithm; and
- a **build half** — vertex/edge construction and an "empty graph of my own
  kind" constructor — implemented by each backend in its native idiom.

Algorithms are written once, against the read half, and run over any backend
that implements it. This is, structurally, what petgraph achieves with its
`IntoNeighbors` / `NodeIndexable` traits: one algorithm body, many graph types.
Erlang reaches the same place through a behaviour instead of a trait.

This reframes the mutability fork. We are not choosing *a* backend; we are
defining the *access contract* and shipping backends behind it. The decisive
property is that the read half is **semantically identical across all
backends** — a neighbour lookup returns a list whether the graph is an immutable
value or a mutable handle — so the value-vs-handle distinction surfaces *only*
in the build half. That asymmetry is what makes the two-tier consumer API
(below) cheap rather than duplicative, and it turns the maps-vs-ETS question
from a fork in graffeo's identity into a packaging question — *which backends
ship in v1* — answerable independently of the algorithm layer.

**Caveat, logged honestly.** A behaviour call is a dynamic `Mod:Fun` dispatch,
so every neighbour lookup pays an indirection that a direct `digraph:` call does
not. For the read-only DFS family this is almost certainly noise next to the
`sets` operations and list construction, but it is the first place to measure if
graffeo is ever pushed onto enormous graphs in a tight inner loop. If it bites,
the standard escapes (per-backend specialised modules, or compile-time
parameterisation) remain open.

## Consumer-facing API: two tiers over one algorithm layer

Because the read half is backend-uniform but the build half is not, graffeo
presents **two construction/mutation tiers** that share **one universal
algorithm layer**. This is deliberately faithful to Erlang's own stdlib, which
already splits the world this way — `lists`/`maps`/`sets` are values;
`ets`/`dets`/`digraph` are handles — so the distinction is native vocabulary
for the user, not a foreign import.

**Tier 1 — functional / value (the blessed front door).** A `graffeo_map`
graph is a true value: copyable, pattern-matchable, message-passable.
Construction and mutation are pure — every operation returns a new graph. This
is the petgraph-like face, and it is the default: `graffeo:new/0` yields a
map-backed value, and the tutorial and front-page examples are all
value-oriented.

**Tier 2 — mutable / handle (transparent over digraph).** A `graffeo_digraph`
or `graffeo_dets` graph is a handle to mutable external state with an owner and
a lifecycle. Operations mutate in place and return `ok`. We do *not* paper over
this with functional-looking signatures: a `digraph` user must be 100%
comfortable with a graffeo-on-digraph graph, which means it behaves exactly
like `digraph` — no hidden copies, no magic. For this tier the user may even
operate on a `digraph` directly; graffeo simply adds the algorithm layer on top.

```erlang
%% Tier 1 (value)
G1 = graffeo:new(),                       % map-backed value
G2 = graffeo:add_edge(G1, a, b),          % returns a NEW graph; G1 untouched

%% Tier 2 (handle)
G  = graffeo_digraph:new(),               % a handle (≈ digraph:new())
ok = graffeo_digraph:add_edge(G, a, b),   % mutates G in place

%% Algorithms — identical call on either tier, because they are reads
Order1 = graffeo:topsort(G1),
Order2 = graffeo:topsort(G).
```

The consequence for the public surface: **`graffeo:*` means "the universal
algorithm layer, plus the functional tier's constructors and operations."** It
is *not* a god-module that also fronts mutation — routing handle-mutation
through the same names would re-introduce exactly the magic we are refusing.
Mutable-tier construction and mutation live in the backend module
(`graffeo_digraph:*`, `graffeo_dets:*`), up to and including just being
`digraph` itself. The graph value is opaque and **carries its own backend
identity**, so every function in `graffeo:*` dispatches through the behaviour
without the user ever naming the backend again after construction.

## Goals

graffeo aims to be the library an Erlang developer reaches for instead of
hand-rolling graph algorithms on top of `digraph`. Concretely: a
backend-agnostic algorithm layer defined against the access behaviour; a
value-oriented primary graph type that feels like petgraph and respects
share-nothing; maximal reuse of the stdlib's existing, battle-tested algorithms
rather than reimplementation for its own sake; and a small, composable
traversal vocabulary that makes the *domain-specific* compositions (the ones no
library ships) cheap to write.

## Non-goals (for now)

graffeo does not aim, in the first cut, to match petgraph's full surface:
multiple physical representations (CSR, adjacency-matrix, stable-index graphs),
flow and matching algorithms, isomorphism, and the heavier centrality measures
are explicitly out until they earn their place. It does not aim to be faster
than `digraph` on mutation-heavy workloads — that is what the ETS backend is
for. And it does not aim to provide a graph *database* or persistence layer;
serialization is a later, separable concern.

## Requirements — seeded by the evidence

The highest-signal input is `fabryk-graph` (in `textrynum`), where graph
algorithms were hand-rolled on petgraph for a real knowledge-graph project. The
inventory is clarifying, and slightly surprising.

Of roughly twelve hand-rolled operations, **only two touch real algorithm
machinery**: a weighted shortest path (A\* over inverted edge weights) and a
topological sort. And toposort is *already* in `digraph_utils`. Everything
else — neighbourhood (n-hop BFS), reverse-dependency traversal, relationship-
filtered neighbour queries, degree centrality, and two bridge-finding
heuristics — is thin composition over BFS/DFS, edge-type filtering, and degree
counting.

Two conclusions follow. First, the genuine algorithmic gap real usage exercised
is narrow: **weighted shortest paths**, plus a **composable, edge-type-filterable
traversal layer with degree/centrality**. Second, several of the most valuable
operations (`find_bridges`, `bridge_between_categories`, a step-numbered
`learning_path`) are *domain-specific and absent from petgraph entirely*. So
"close the gap to petgraph" is necessary but not sufficient: the differentiator
is making these compositions easy to hand-roll — good traversal primitives,
weight-aware paths, first-class reverse traversal — not shipping every named
algorithm.

This yields the functional requirements:

| # | Requirement | Source of evidence |
|---|---|---|
| R1 | A graph-access behaviour: the read surface the ported algorithms need (`vertices`, `in_neighbours`, `out_neighbours`, `in_degree`, `no_edges`, `no_vertices`), plus `out_degree` for the degree layer (R7), plus the constructive ops needed to build result graphs. | digraph_utils structure |
| R2 | A maps-backed immutable graph value implementing the behaviour, with a builder API; labels on vertices and weights on edges. | share-nothing fit; fabryk's value model |
| R3 | A `digraph`/ETS adapter implementing the behaviour, for reuse and scale. | stdlib reuse |
| R4 | Reuse of the `digraph_utils` algorithm family via the behaviour: components, strong components, reachability/reaching, topsort, acyclicity, pre/postorder, tree/arborescence. | digraph_utils inventory |
| R5 | Weighted shortest paths: Dijkstra and A\*, with a pluggable edge-cost function. | fabryk `shortest_path` |
| R6 | A composable traversal layer: BFS/DFS that accept a direction (out/in/both) and an edge/relationship-type filter predicate, yielding nodes with distances. | fabryk `neighborhood`, `dependents`, `get_related` |
| R7 | Degree-based metrics: in/out/total degree, normalised degree centrality, top-k by degree. | fabryk `calculate_centrality`, stats |
| R8 | First-class reverse traversal (in-edges) as a peer of forward traversal. | fabryk `dependents`, `reaching` |

## Scope: an evidence-driven first cut, then earned expansion

**First cut (the vertical slice).** R1–R8. The access behaviour; the maps
backend (primary) and `digraph` adapter (reuse); the ported `digraph_utils`
family running over the behaviour; weighted shortest paths; the
filter-aware traversal and degree layer. This is deliberately the *evidence
band* — what real usage proved necessary — not the petgraph checklist. It ships
end-to-end and exercises the architecture under load.

**Earns-its-place (next).** The petgraph "must-have" remainder that the
evidence did not force but that rounds out the library: minimum spanning
trees (Kruskal/Prim), an own-implementation of SCC if we want to decouple from
`digraph_utils`' choice, cycle enumeration, weakly-connected components via
union-find, all-simple-paths.

**Later / if earned.** All-pairs shortest paths (Floyd–Warshall, Johnson),
bidirectional Dijkstra, articulation points and bridges (the *algorithm*, distinct
from fabryk's heuristic), graph coloring, dominators, PageRank, max-flow/min-cut,
matching, isomorphism, alternate physical representations, DOT/serde-style I/O.
None of these block the first cut, and each should be justified by a concrete
need before it lands.

## Module namespace

The façade means users touch one module — `graffeo` — so internal
decomposition is *free* to them, and we split by responsibility from the start
rather than hiding algorithms in a `_utils` junk drawer. (The `digraph_utils`
name is grandfathered; we decline to inherit the smell.)

| Module | Role | Public? |
|---|---|---|
| `graffeo` | The façade: the universal algorithm layer + Tier-1 (`graffeo_map`) constructors and operations. The one module most users touch. | Yes — primary |
| `graffeo_backend` | The access *behaviour* — the read-half/build-half callback contract. The architectural keystone and the extension point for new backends. | Yes — backend authors |
| `graffeo_map` | Tier-1 value backend (default). | Yes — construction |
| `graffeo_digraph` | Tier-2 handle backend over stdlib `digraph`/ETS; the reuse + scale path. | Yes — construction |
| `graffeo_dets` | Tier-2 handle backend over `dets` (on-disk / persistent). | Later band |
| `graffeo_path` | Weighted shortest paths (R5): Dijkstra, A\*. | Internal (fronted by `graffeo`) |
| `graffeo_conn` | Connectivity (R4): components, strong components, reachability/reaching, tree/arborescence. | Internal |
| `graffeo_traverse` | Traversal (R4, R6, R7): BFS/DFS, pre/postorder, direction-and-filter-aware walks, degree/centrality. | Internal |

`graffeo_span` (spanning trees) and `graffeo_flow` (max-flow) belong to the
earns-its-place / later bands; they slot in as new internal modules fronted by
the same façade when their algorithms land. The earlier worry about "too many
modules early" no longer applies: with the façade, module count is a
maintainer's concern, and maintainers want the separation.

## Open questions that remain

The fork is resolved and the API shape is settled, but real choices are still
live, and naming them is part of the work rather than a failure to finish it.

The build half's exact packaging. We've committed to splitting the contract
into a read half (universal) and a build half (per-backend), but whether that
is one behaviour with two callback groups or two distinct behaviours
(`graffeo_backend` for reads, a separate constructive behaviour) is open. The
constructive stdlib algorithms (`subgraph/3`, `condensation/1`) need the build
half; a read-only backend should not be forced to implement it, which leans
toward two behaviours.

How much of Tier 2 graffeo wraps. For the handle tier we can mirror `digraph`'s
full mutation API under `graffeo_digraph:*` (drop-in familiarity, more surface)
or expose only construction and let users mutate via `digraph` directly
(maximally transparent, less surface). The transparency goal leans toward the
latter; a thin mirror may still aid discoverability. To be decided when
`graffeo_digraph` is built.

The maps backend's representation is open: a plain nested map, a pair of maps
(adjacency + reverse-adjacency) to make in-neighbour lookup O(1), or a record
wrapping both. R8 (first-class reverse traversal) argues for storing reverse
adjacency explicitly rather than computing it.

The edge-cost contract for R5 needs a type: a fixed `number()` weight, or a
user-supplied `fun((Edge) -> number())` as petgraph does, or both. fabryk's
inverted-weight trick (cost = `1 / max(weight, ε)`) suggests the function form
is the right general primitive.

## Risks

The dispatch-indirection cost (above) is the one performance risk worth
watching, and it is measurable rather than speculative. The larger project risk
is scope drift toward the petgraph checklist before the evidence band is solid —
the prospectus's own discipline (resolve the fork, then build a vertical slice)
is the mitigation. A smaller risk: if `digraph_utils`' algorithm *choices*
(e.g. which SCC variant, the arbitrary component ordering) do not match what we
want to expose, reuse becomes reimplementation, and R4's value shrinks. The
first milestone surfaces that early by porting at least one non-trivial member
of the family.

## Milestone 1 — the vertical slice

The proof-of-architecture, end-to-end:

1. Define `graffeo_backend` — the read half first (the universal accessors),
   then the build half for the map backend.
2. Implement `graffeo_map` (Tier 1) with its functional builder; labels on
   vertices, weights on edges.
3. Implement `graffeo_digraph` (Tier 2) over stdlib `digraph`.
4. Port one non-trivial connectivity/sort algorithm (topological sort or strong
   components) to run over the read half, and verify it produces identical
   results on a Tier-1 value graph and a Tier-2 handle graph.
5. Implement Dijkstra (R5) over the read half.
6. Implement direction-and-filter-aware BFS (R6) and degree centrality (R7).
7. Tests that run the *same* `graffeo:*` algorithm suite against both a value
   graph and a handle graph — the strongest possible evidence that the seam,
   and the universal algorithm layer, are real.

Only after the slice holds do we open the earns-its-place band.

---

*Status: pre-implementation, fork resolved. The architecture is committed; the
scope is bounded by evidence; the open questions are scoped and named.*
