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
`graffeo_ets` (mutable, implemented over the stdlib `digraph`); and a `dets` on-disk
backend on the way. The design rationale lives in
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

*More on the way* — an edge-induced subgraph (`filter_edges/2`) and vertex
contraction (`contract/2,3`) are landing next, with minimum spanning trees,
negative-weight shortest paths (Bellman-Ford), and the `dets` backend on the
roadmap.

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

## Status

**0.1.0 — full stdlib parity, and then some.** graffeo now implements the
*entire* `digraph` and `digraph_utils` algorithm surface, plus weighted A\*, and
every function runs over *both* tiers — the functional map value (default) and
the ETS-backed handle (`graffeo_ets`). All of the following is implemented and tested (eunit, Common Test + PropEr):

**Building & access**

- the graph-access behaviour and its two backends — the functional map value
  (default) and the ETS-backed handle (`graffeo_ets`);
- vertices and edges with labels and edge metadata; in/out neighbours;
- handle-tier mutation in one namespace — `add_vertex/2,3`, `add_edge/3,4`,
  `del_vertex/2`, `del_vertices/2`, `del_edge/3`, `del_edges/2`, plus `wrap/1`,
  `unwrap/1`, and `delete/1`.

**Shortest paths & weights**

- Dijkstra (`dijkstra/2,3`) with a pluggable cost function;
- weighted A\* (`astar/3,4`) with a pluggable cost function and an admissible
  heuristic — the default-zero heuristic degenerates cleanly to Dijkstra.

**Path & cycle queries** (faithful ports of `digraph`)

- `get_path/3`, `get_cycle/2`, `get_short_path/3`, `get_short_cycle/2`,
  `source_vertices/1`, `sink_vertices/1`.

**Connectivity & DFS family** (faithful ports of `digraph_utils`)

- `components/1`, `strong_components/1`, `cyclic_strong_components/1`;
- `reachable/2`, `reachable_neighbours/2`, `reaching/2`,
  `reaching_neighbours/2`;
- `is_acyclic/1`, `is_tree/1`, `is_arborescence/1`, `arborescence_root/1`,
  `loop_vertices/1`, `preorder/1`, `postorder/1`.

**Constructive & metrics**

- `subgraph/2,3` and `condensation/1`, each returning a graph of the same
  backend as its input;
- breadth-first traversal with direction (`out`/`in`/`both`) and an edge-type
  filter, returning distances; degree metrics — in/out/total degree, normalised
  degree centrality, top-k; first-class reverse traversal.

Every ported function is checked for **exact parity** with its stdlib
counterpart on the handle backend, and for **cross-tier parity** between the two
backends — so "one algorithm layer, many backends" is enforced, not merely
asserted. (The one documented exception is `get_short_path/3`, which guarantees
shortest length, valid path, correct endpoints, and reachability agreement, but
may pick a different equally-short path than `digraph` when several exist — see
[`docs/design/`](docs/design/) for why.)

On the roadmap: minimum spanning trees, negative-weight shortest paths
(Bellman-Ford), a `dets` on-disk backend, and multi-edge support — graffeo
currently models *simple* directed graphs (at most one edge per ordered pair).
Expect the public API to keep moving as these land. The design thinking lives in
[`docs/design/`](docs/design/).

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
