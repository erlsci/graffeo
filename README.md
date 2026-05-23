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

{ok, _Order}  = graffeo:topsort(G),       %% a valid topological order, e.g. [a, b, c, d]
{Dist, _Prev} = graffeo:dijkstra(G, a),   %% #{a => 0, b => 1, c => 3, d => 6}
3             = graffeo:degree(G, c),      %% in: a, b (2) + out: d (1)
[{a, 0} | _]  = graffeo:bfs(G, a).         %% [{Vertex, Distance}], breadth-first from the source
```

Because the graph is a plain value, `G0` still has zero edges after all of the
above — nothing was mutated, and `G` can be pattern-matched or sent between
processes like any other term.

### Handle tier (`digraph`/ETS, transparent and mutable)

```erlang
%% A mutable handle over digraph — ETS-backed and owned by your process.
D = digraph:new(),
graffeo_digraph:add_edge(D, a, b, #{weight => 1}),
graffeo_digraph:add_edge(D, b, c, #{weight => 2}),
graffeo_digraph:add_edge(D, a, c, #{weight => 10}),
graffeo_digraph:add_edge(D, c, d, #{weight => 3}),

%% Wrap once to get the algorithm layer — the SAME graffeo:* calls.
G = graffeo_digraph:wrap(D),
{ok, _Order}  = graffeo:topsort(G),
{Dist, _Prev} = graffeo:dijkstra(G, a),   %% #{a => 0, b => 1, c => 3, d => 6}

digraph:delete(D).   %% you own the handle's lifecycle
```

`graffeo_digraph:wrap/1` also lifts a `digraph` you already have — it just adds
the algorithm layer on top and changes nothing about how the handle behaves.

## Status

**0.1.0 — the first vertical slice.** graffeo is young but real, and ready to
try. Implemented, and tested across *both* tiers:

- the graph-access behaviour and its two backends — the functional map value
  (default) and the `digraph`/ETS handle;
- topological sort;
- weighted shortest paths (Dijkstra, with a pluggable cost function);
- breadth-first traversal with direction (`out`/`in`/`both`) and an edge-type
  filter, returning distances;
- degree metrics — in/out/total degree, normalised degree centrality, top-k;
- first-class reverse traversal.

The test suite runs every algorithm over both backends (eunit + Common Test +
PropEr), so the "one algorithm layer, many backends" claim is enforced rather
than merely asserted.

Not here yet, and on the near roadmap: the rest of the `digraph_utils` family
(components, strong components, reachability), A\*, minimum spanning trees, a
`dets` on-disk backend, and multi-edge support — graffeo currently models
*simple* directed graphs (at most one edge per ordered pair). Expect the public
API to keep moving as these land. The design thinking lives in
[`docs/design/`](docs/design/).

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
