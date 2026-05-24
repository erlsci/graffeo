# graffeo — Architecture

> **Seed content.** The "Design overview" below is migrated verbatim from the
> README's original *The idea* section; it is the kernel of a fuller architecture
> document. The "To expand" list at the end records the sections still to be
> written, so this file can grow into the real thing rather than being rewritten.

## Design overview

Two design choices shape graffeo.

**One algorithm layer, many backends.** The Erlang stdlib's algorithms
were written functional-first: they touch storage only through a thin set of
read accessors and never mutate the graph they traverse. graffeo makes that
implicit seam explicit as an Erlang *behaviour*, so each algorithm is written
once and runs over any backend that satisfies the contract. This is the same
property that the Rust library `petgraph` gets from its graph traits — one
algorithm body, many graph types — `graffeo` does this the Erlang way.

**Two tiers, faithful to Erlang.** The standard library already splits the
world into values (`lists`, `maps`, `sets`) and handles (`ets`, `dets`,
`digraph`), and graffeo honours that rather than hiding it:

- a **functional tier** — an immutable, map-backed graph that is a true value:
  copyable, pattern-matchable, and message-passable between processes (the
  default, and the petgraph-like face); and
- a **handle tier** — a mutable backend over `digraph`/ETS (and, later, `dets`
  on disk) for scale and for drop-in transparency. A `digraph` user should be
  completely at home here, because nothing magic happens underneath.

The algorithms are shared across both tiers, because reading a graph is the
same whether it is a value or a handle. The difference shows up only where it
genuinely matters — in how you build and change a graph.

## To expand

- **The `graffeo_backend` behaviour** — the read half (universal accessors every
  algorithm uses) and the build half (per-backend construction), and why they are
  split.
- **The backends** — `graffeo_map` (the immutable value), `graffeo_digraph` (the
  `digraph`/ETS handle), and `graffeo_dets` (on-disk, on the way): their semantics,
  lifecycles, and trade-offs.
- **The envelope and façade dispatch** — how the opaque `graffeo:graph()` carries its
  own backend identity so the façade dispatches without the caller naming a backend.
- **The simple-graph contract and edge-metadata model** — at most one edge per
  ordered pair; `weight` and arbitrary `label` data on edges.
- **Parity as an enforced invariant** — cross-tier parity (value ≡ handle) and
  stdlib parity (ported functions ≡ `digraph`/`digraph_utils`), and how the test
  suite enforces them.
- **Performance notes** — the dynamic-dispatch indirection per neighbour lookup, and
  when it matters.
