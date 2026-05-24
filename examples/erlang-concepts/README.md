# erlang-concepts — a worked example for graffeo

This example builds a real graph from real data and runs graffeo's full algorithm
surface over it. The data is the **Erlang concept-card knowledge base** from
[`billosys/ai-engineering`](https://github.com/billosys/ai-engineering): 1,664
cards distilled from twelve canonical Erlang/OTP sources (*Learn You Some Erlang*,
*Programming Erlang*, the OTP Design Principles, *Designing for Scalability with
Erlang/OTP*, *Erlang in Anger*, the Inaka guidelines, and more), each a Markdown
file with typed relationships in its front matter.

It is two things at once. As an example, it shows graffeo used the way you'd use it
on your own data — build a graph, ask questions, get answers. As the second half of
this README, it's a guided tour: a chapter that starts in territory a working Erlang
programmer already owns and walks, step by step, toward the graph theory underneath.

## What you'll need

- Erlang/OTP 27+ and `rebar3`.
- The corpus, fetched once (a shallow clone pinned to a tag; ~13 MB, not vendored).
  Run these **from this directory** (`examples/erlang-concepts`):

```shell
make fetch-cards      # clones billosys/ai-engineering@0.1.0 into ../../workbench/ai-engineering
make example          # compiles the example and runs the full query catalog
```

`make example` prints the whole catalog at once. The tour below pulls it apart so
you can run each piece yourself and see *why* each number is what it is.

## Project layout

```
examples/erlang-concepts/
  src/
    erlc_parser.erl    % tolerant reader for the cards' non-standard front matter
    erlc_ingest.erl    % cards -> the two-layer graffeo graph (deterministic)
    erlc_queries.erl   % the query catalog
    erlc.erl           % the runner behind `make example`
  oracle/
    src/main.rs        % an independent Rust (petgraph) reference for every figure here
    expected.json      % frozen expected results; regenerate with `make oracle-gen`
  test/                % eunit for the parser, ingestion, and queries
```

Every figure quoted in this document comes from `oracle/expected.json` — an
independent re-implementation, so the Erlang and the Python have to agree before a
number is trusted. (They didn't, once; the disagreement found a real bug. That's the
point of keeping two.)

## How the graph is modelled

One graffeo graph carries **two layers**:

- a **source layer** — one vertex per card, keyed `{SourceSlug, Slug}` (e.g.
  `{<<"programming-erlang">>, <<"gen-server">>}`), wired with that book's own local
  relationship edges;
- an **abstract layer** — one vertex per *concept*, keyed by the bare `Slug` (e.g.
  `<<"gen-server">>`), whose edges are **derived** by projecting the source edges
  upward and unioning across books;

joined by **membership** edges `{SourceSlug, Slug} -> Slug` (`instance_of`). The
abstract layer is the only bridge between books, so two books' takes on the same
concept meet only by going up to the shared concept and back down. Relationship type
(`prerequisites`, `related`, `extends`, `contrasts_with`) lives in each edge's
metadata as a *set*, and the vertex's *shape* tells you its layer — a tuple is a
card, a bare binary is a concept. (The full rationale is in the milestone definition
under the project's `workbench/`.)

---

# A guided tour of the Erlang knowledge graph

> The tour climbs deliberately. The first sections assume you know OTP and lean on
> that intuition; the later ones assume nothing but willingness and build up the
> graph theory — strongly connected components, condensation, partial orders — from
> the data in front of you. Start where you're comfortable; the rungs are close
> together.

Fire up a shell from this directory and build the graph once. Everything below
operates on `G`:

```erlang
%% cd examples/erlang-concepts && rebar3 shell
1> R = erlc_ingest:build_from_dir(
1>     "../../workbench/ai-engineering/knowledge/erlang/concept-cards").
2> G = maps:get(graph, R).
3> graffeo:no_vertices(G).
3061
```

## 1. What did we just load?

A graph with two kinds of vertex. Ask graffeo to separate them:

```erlang
4> length(erlc_ingest:source_vertices(G)).   %% the cards
1664
5> length(erlc_ingest:abstract_vertices(G)). %% the concepts (incl. 3 ghosts; see §6)
1397
```

1,664 cards collapse to **1,394 distinct carded concepts** (`maps:get(abstract_count, R)`)
— because some concepts (`gen-server`, `pattern-matching`) are documented in several
books at once. The abstract layer carries three vertices beyond those: *ghost*
concepts, referenced but never written up, which we meet in §6. Hold the collapse in
mind; it drives half of what follows. The abstract relationships break down by type
like this (from the oracle):

| type | count | reading |
|------|------:|---------|
| `related` | 3917 | "see also" |
| `prerequisites` | 2158 | "you need X first" |
| `contrasts_with` | 591 | "don't confuse X with Y" |
| `extends` | 299 | "X is a special case of Y" |

If you've written an OTP release, this is just a bigger `*.app` dependency graph with
nicer labels. So let's ask the questions you'd ask of any dependency graph.

## 2. Which concepts carry the most weight?

In a supervision tree you can eyeball the load-bearing process. Here the graph tells
you, by **degree** — how many relationships touch a concept:

```erlang
6> erlc_queries:top_concepts_by_degree(G, 5).
[{<<"gen-server">>,118},
 {<<"pattern-matching">>,92},
 {<<"otp-application">>,86},
 {<<"message-passing">>,84},
 {<<"supervisor">>,68}]
```

No surprise to anyone who's shipped Erlang: `gen_server`, pattern matching, message
passing, applications, supervisors. The graph recovers the OTP "syllabus" from raw
cross-references, with nobody having ranked anything by hand. Degree is the crudest
centrality measure there is, and it already works because the corpus is honest about
what connects to what.

## 3. Neighbourhoods, and a tunable notion of "related"

Degree is a count; the neighbours themselves are more interesting. Ask what
`gen-server` is *built on*:

```erlang
7> graffeo:out_neighbours(G, <<"gen-server">>).
%% includes: behaviour, callback-module, generic-server, message-passing,
%%           otp-behaviours, client-server-model, process-state-loop, ...
```

Now here's where the two-layer model earns its keep. "What's related to `gen-server`?"
has *two* honest answers, and graffeo lets you choose your radius. The cheap one stays
inside a single book:

```erlang
8> erlc_queries:related_cheap(G, <<"programming-erlang">>, <<"gen-server">>).
```

The expensive one goes up to the shared concept, back down to every *other* book's
card for `gen-server`, and unions in what each of those books linked to. The clearest
illustration is a smaller concept, `anonymous-variable`:

```erlang
9>  erlc_queries:related_cheap(G,    <<"erlang-otp-action">>, <<"anonymous-variable">>).
[<<"variable">>]
10> erlc_queries:related_extended(G, <<"erlang-otp-action">>, <<"anonymous-variable">>).
[<<"list">>,<<"single-assignment-variable">>,<<"tuple">>,
 <<"underscore-prefixed-variables">>,<<"variable">>]
```

*Erlang/OTP in Action* links anonymous variables only to "variable." Pool the other
books' views through the shared concept and you also learn they tie to single
assignment, tuples, lists, and the underscore convention — context one book never gave
you. Cheaply local or expensively global; same data, your call. (Under the hood the
extended query is a composed walk — forward along membership, then *reverse* down to
sibling cards — which is exactly the first-class reverse traversal graffeo provides.)

## 4. Is the knowledge one body or an archipelago?

This is the first genuinely graph-theoretic question, and the word for it is
**connected components**: maximal sets of concepts you can reach from one another if
you ignore edge direction. Ask it of the `related` edges:

```erlang
11> {Count, Giant, _Comps} = erlc_queries:related_components(G).
12> {Count, Giant}.
{19, 1151}
```

Nineteen components, one of them a giant of 1,151 concepts — the connected core of
Erlang knowledge. The eighteen others are islands, and *which* islands is the payoff.
The largest satellite (121 concepts) is the **coding-style** corpus —
`avoid-case-catch`, `camelcase-variables`, `100-column-line-limit` — the Inaka and
programming-rules material, almost untouched by the rest because style guides cite
style guides. A smaller island is **tracing and diagnostics** (`recon-trace`,
`match-specification`, `tracing-principles`). The graph has sorted the knowledge into
its natural neighbourhoods.

Now widen the relation. Count components again, but over *all four* edge types, not
just `related`:

```erlang
13> {C2, G2, _} = erlc_queries:semantic_components(G).
14> {C2, G2}.
{10, 1212}
```

Nineteen components fall to **ten**; the giant grows from 1,151 to 1,212. Nine islands
just got bridged — and they were bridged by `prerequisites`, `extends`, and
`contrasts_with` edges, not by "see also." That delta (19 → 10) is itself a finding:
it measures how much of the knowledge graph hangs together only once you count the
*structural* relationships, not merely the associative ones.

## 5. Reachability: the full weight behind a concept

Components ignore direction. Prerequisites do not — "you need X first" is an arrow.
Following those arrows transitively answers: *everything you must understand before
you can claim to understand this concept.* That's **reachability**.

graffeo's `reachable/2` computes it over whatever graph you hand it. Hand it the
prerequisite edges (the example builds that projection internally for the queries in
§6) and the transitive closure of `gen-server` comes to **57 concepts**. Here's the
arresting part: do the same for `supervisor` and for `supervision-tree` and you get
the *same 57*. Three different starting points, one identical prerequisite universe.

That's not a coincidence, and it's not a bug. It's the graph telling you these three
concepts are knotted together so tightly that none truly precedes the others — you
cannot learn `gen-server` strictly before `supervisor` if each lists the other as a
prerequisite. To name what's happening, we need one more idea.

## 6. Cycles, condensation, and the order that survives them

Read literally, "prerequisite" should describe a graph with no cycles — a partial
order, where if X comes before Y then Y never comes before X. Test it:

```erlang
15> {IsCyclic, Cycles} = erlc_queries:prerequisite_cycles(G).
16> {IsCyclic, length(Cycles)}.
{true, 12}
```

It is **not** acyclic. There are twelve **strongly connected components** of size > 1
— twelve clusters where every concept is (transitively) a prerequisite of every other.
Most are mutual pairs (`event-handler ⇄ gen-event-behavior`, `ct-test-case ⇄
ct-test-suite`), but one is a ten-concept tangle: `supervisor`, `gen-server`,
`child-specification`, `behaviour`, `supervision-tree`, `worker-process`, and four
more, all mutually entangled. *That* is why §5's three closures were identical — those
three concepts live in this single SCC, so they share one prerequisite universe by
definition.

Whether each cycle is a real modelling defect or a fair statement that two ideas are
co-requisite is a judgement call — but the graph has localised all twelve for you to
adjudicate, which is the hard part done.

And you can still extract a teaching order, because there's a classical move for
exactly this. **Condensation** collapses each strongly connected component to a single
super-vertex; the result is guaranteed acyclic — a DAG — and a DAG always has a
**topological order**:

```erlang
17> {ok, Order} = erlc_queries:learning_order(G).
18> length(Order).
1204
```

The 34 entangled concepts collapse into 12 super-vertices, leaving a 1,204-node DAG
that sorts cleanly. One precision note for the careful reader: the prerequisite edge
runs *concept → prerequisite*, and `graffeo:topsort/1` places the tail of each edge
before its head — so `Order` lists each concept *ahead of* the things it depends on. A
study sequence (foundations first) is that list reversed. The mathematics doesn't care
which way you read a total order; you do, so reverse it before you hand it to a
student.

## 7. Going further: weighting the graph

Everything so far has been structural — edges present or absent. graffeo also carries
weighted shortest paths (`dijkstra/2,3`, `astar/3,4`) with a pluggable cost function,
which opens a different question: not *can* you get from concept X to concept Y, but
what's the *gentlest* path — the route through the fewest unfamiliar ideas. This
example doesn't ship a weighting (the cards assert no weights), but the shape of the
extension is small and worth sketching as an exercise: assign each prerequisite edge a
cost — say `1 / coverage(target)`, so well-documented stepping stones are "cheap" —
build that weighted projection, and run `graffeo:astar/4` from a concept you know to
one you don't. The result is a minimal-surprise learning path. The metric is yours to
design; graffeo supplies the search.

## Exercises

1. **Most central within one book.** Restrict to a single source's cards and rank by
   degree. Does *Learn You Some Erlang* foreground different concepts than the OTP
   Design Principles?
2. **Lonely concepts.** 1,213 of the 1,394 concepts appear in exactly one book. Find
   the ones that are *also* graph leaves (no outgoing relationships) — the genuinely
   isolated ideas.
3. **The ghosts.** `erlc_queries:ghost_concepts(G)` returns three concepts referenced
   as prerequisites but documented in no book (`erlang-ports`, `os-monotonic-time`,
   `os-system-time`). What should the corpus do about them?
4. **Longest chain.** In the condensed (acyclic) prerequisite graph, find the longest
   path — the deepest prerequisite stack in all of Erlang/OTP.

## Where to go next

The algorithms used here — `components`, `cyclic_strong_components`, `condensation`,
`topsort`, `top_k_by_degree`, `out_neighbours`/`in_neighbours`, `reachable` — are the
graffeo public surface; see the top-level project for the full API. This same example
is also the acceptance harness for graffeo's forthcoming on-disk (`dets`) backend:
because every query above is written against the `graffeo:*` façade and never names a
backend, it will run unchanged over a persisted graph, and the three backends must
return identical answers.
