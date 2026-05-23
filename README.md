# graffeo

[![Build Status][gh-actions-badge]][gh-actions]
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

## The idea

Two design choices shape graffeo.

**One algorithm layer, many backends.** The Erlang stdlib's algorithms
were written functional-first: they touch storage only through a thin set of
read accessors and never mutate the graph they traverse. graffeo makes that
implicit seam explicit as an Erlang *behaviour*, so each algorithm is written
once and runs over any backend that satisfies the contract. This is the same
property that the Rust library `petgraph` gets from its graph traits — one algorithm body, many graph
types — `graffeo` does this the Erlang way.

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

## Status

Early. graffeo is in the design phase: the architecture and scope are written
down, but the implementation has not begun. The thinking lives in
[`docs/design/`](docs/design/), starting with the project prospectus and the
project-definition document. Expect the public API to move as the first vertical
slice is built.

## Build

```shell
rebar3 compile
```

## License

Apache License 2.0. See [LICENSE.md](LICENSE.md).

[//]: ---Named-Links---

[logo]: priv/images/logo.png
[logo-large]: priv/images/logo-large.png
[gh-actions-badge]: https://github.com/erlsci/graffeo/workflows/ci/badge.svg
[gh-actions]: https://github.com/erlsci/graffeo/actions?query=workflow%3Aci
[tag-badge]: https://img.shields.io/github/tag/erlsci/graffeo.svg
[tag]: https://github.com/erlsci/graffeo/tags
