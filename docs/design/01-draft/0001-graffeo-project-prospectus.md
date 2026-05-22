---
number: 1
title: "graffeo — project prospectus"
author: "Duncan McGreggor"
component: All
tags: [change-me]
created: 2026-05-22
updated: 2026-05-22
state: Draft
supersedes: null
superseded-by: null
version: 1.0
---

# graffeo — project prospectus

*A working sketch, not a contract. Meant to be argued with.*

## What it is

An Erlang library that wraps the two stdlib digraph modules — `digraph` and
`digraph_utils` — and closes the gap to [petgraph](https://docs.rs/petgraph),
the Rust graph library that has set the recent bar for "batteries included."
Where `digraph_utils` stops (it gives you topological sort, components, reachability,
cycle detection, and little else), `graffeo` carries the rest: weighted shortest
paths, minimum spanning trees, richer connectivity, traversal abstractions, and
the assorted algorithms one ends up hand-rolling on real graph projects.

The personal stamp — and the part that makes this *yours* rather than "petgraph.erl"
— is folding in the algorithms you've already had to implement on top of petgraph.
Those are the proof of what's actually missing, as opposed to what a feature
checklist says should be there.

## The name

`graffeo`, after the San Francisco roaster (Sicilian founder, Little Italy, 1935)
whose dark roast has been a quarterly fixture for 12+ years — and, not by
coincidence, a true etymological cognate of *graph*: the surname descends from
Greek *grapheus* ("scribe"), from *graphein* ("to write / scratch / incise"),
the same root that gives graph theory its name. A graph library named for the
word "graph" comes from. The espresso is a bonus.

(Trademark-shadow caveat, logged honestly: searches for "graffeo" will surface
beans before BEAM for a while. On hex.pm this is a non-issue; in casual
conversation it's a feature with a good story attached.)

## Open design questions (flagged, not resolved)

### 1. Mutable vs. persistent — the load-bearing fork

This is the decision everything else leans on, and the name deliberately doesn't
settle it.

- **`digraph` is mutable.** It's an ETS-backed structure behind a process-owned
  handle. The graph is a *thing you mutate*, not a value you pass around.
- **petgraph is value-oriented.** Its whole feel is "the graph is a value you
  own, clone, and hand off." Immutable-by-default ergonomics.

A wrapper can paper over a lot, but not this. The ported algorithms will *assume*
one model — a functional fold over an immutable structure reads very differently
from operations that mutate ETS in place. Three broad stances:

- **(a) Stay faithful to `digraph`** — embrace mutability, be the "digraph and
  then some" library. Lowest friction over the substrate; least petgraph-like feel.
- **(b) Offer a value-oriented layer** over (or instead of) `digraph` —
  petgraph-faithful ergonomics, more work, possibly a second backend (e.g. `maps`).
- **(c) Two faces, one library** — a mutable core with a value-oriented facade.
  Tempting; risks doing neither cleanly.

Recommendation: **decide this before porting any algorithm**, because the porting
cost is paid in whichever model you pick.

### 2. Module namespace

The library is `graffeo`; the modules are a separate choice. Some candidates:

| Module | Mirrors / role |
|---|---|
| `graffeo` | top-level entry; mirrors `digraph` |
| `graffeo_utils` | mirrors `digraph_utils`; the "extra algorithms" home |
| `graffeo_path` | shortest paths (Dijkstra, Bellman-Ford, A*, Floyd-Warshall) |
| `graffeo_span` | spanning trees / forests (MST: Kruskal, Prim) |
| `graffeo_conn` | connectivity (SCC, bridges, articulation points, k-conn) |
| `graffeo_traverse` | BFS/DFS as composable traversals / iterators |
| `graffeo_flow` | max-flow / min-cut, if it earns its place |

The `digraph` / `digraph_utils` parallel (i.e. `graffeo` / `graffeo_utils`) is the
cheap, legible signal of lineage. Whether to split further into the per-domain
modules above, or keep it to two and let `graffeo_utils` get large, is a real
choice — easier to split later than to merge, so erring toward fewer modules
early is defensible.

### 3. Scope of the petgraph homage

Not everything in petgraph deserves a port. Worth deciding what's **in** for a
first cut vs. **later**:

- **Likely in:** weighted shortest paths, MST, strongly/weakly connected
  components, topo sort (delegate to stdlib where it already exists), basic
  traversals.
- **Earns-its-place / later:** centrality measures, max-flow, matching,
  graph isomorphism, the `StableGraph` analogue (stable indices across removal).
- **Your hand-rolled set:** to be inventoried — these are the highest-signal
  additions because you already know you needed them.

## Immediate next steps

1. **Toast the name.** ✅ Done.
2. **Resolve the mutability fork (Q1).** Everything downstream depends on it.
3. **Inventory the hand-rolled petgraph algorithms** — the real requirements doc
   hides here.
4. **Pin the module namespace (Q2)** once the model is chosen.
5. Only then: first algorithm port, as a vertical slice that exercises the chosen
   model end-to-end.

---

*Status: pre-implementation. Open questions outnumber answers by design.*
