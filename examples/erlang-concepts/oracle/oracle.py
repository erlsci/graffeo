#!/usr/bin/env python3
"""Independent expected-results oracle for the erlang-concepts example.

This is the *reference* against which the Erlang example's output is checked. It
is built independently of the Erlang implementation on purpose: CC writes the
Erlang ingestion/queries, this oracle computes the same facts in Python, and CDC
diffs the two. Do NOT edit this to match the Erlang output — if they disagree,
one parse is wrong and that investigation is the QA loop.

It implements the agreed model:

  * Source layer  : one vertex per card file, id {SourceSlug, Slug}.
  * Abstract layer: one vertex per unique slug; abstract relation edges are the
                    *projection* of every card's typed references onto
                    (slug -> target-slug), unioned across books.
  * Edge types    : prerequisites / extends / related / contrasts_with.

Projection conventions (must match the Erlang ingestion exactly):
  * Component / cycle / degree projections are EDGE-INDUCED: a projection graph
    contains only the vertices incident to an edge of the relevant type. Isolated
    concepts are not added as singletons.
  * "components" is undirected (weakly-connected) over the `related` projection.
  * "cyclic strong components" are the non-singleton SCCs of the `prerequisites`
    projection (matches graffeo:cyclic_strong_components/1).
  * "top-k by degree" is TOTAL degree (in+out) over the union of all four
    abstract relation edge types (matches graffeo:top_k_by_degree/2).

Usage:
    python3 oracle.py [CARDS_DIR] [--json]

CARDS_DIR defaults to ../../../workbench/ai-engineering/knowledge/erlang/concept-cards
(the location `make fetch-cards` clones to). Output is canonical (sorted keys,
sorted lists) so it is stable and diffable.
"""

import sys
import os
import re
import glob
import json
import collections

REL_KEYS = ["prerequisites", "extends", "related", "contrasts_with"]
TOP_K = 12

DEFAULT_CARDS = os.path.normpath(
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "..", "..", "..", "workbench", "ai-engineering",
        "knowledge", "erlang", "concept-cards",
    )
)


def front_matter(text):
    """Return the front-matter block of a card.

    The dialect is non-standard: a doubled `---`/`---` opener, then
    `# === SECTION ===` comment headers interleaved with `key: value` lines and
    `- item` lists, closing at the `---` before the body. We take the first
    `---`-delimited block that carries `slug:` or `concept:`.
    """
    for part in text.split("---"):
        if "slug:" in part or "concept:" in part:
            return part
    return ""


def slug_of(fm, path):
    m = re.search(r"^\s*slug:\s*(.+)$", fm, re.M)
    if m:
        return m.group(1).strip().strip('"')
    return os.path.splitext(os.path.basename(path))[0]


def list_field(fm, key):
    # Match ONLY the key line: the whitespace after the colon must be horizontal
    # ([ \t]*), never \s* — \s* crosses the newline and swallows the first
    # block-list item (the bug CC found). Then handle inline vs block form.
    m = re.search(rf"^[ \t]*{key}:[ \t]*(.*)$", fm, re.M)
    if not m:
        return []
    inline = m.group(1).strip()
    if inline.startswith("["):  # inline list, e.g. `contrasts_with: []`
        body = inline.strip("[]").strip()
        return [x.strip().strip('"') for x in body.split(",") if x.strip()] if body else []
    if inline:  # bare inline scalar (rare for these fields)
        return [inline.strip('"')]
    out = []  # block form: `- item` on the following lines
    for line in fm[m.end():].splitlines():
        stripped = line.strip()
        if re.match(r"^[a-z_]+:", stripped):
            break  # next key
        g = re.match(r"^-\s*(.+)$", stripped)
        if g:
            out.append(g.group(1).strip().strip('"'))
    return out


def tarjan_scc(adj, nodes):
    """Strongly-connected components via iterative Tarjan. Deterministic."""
    index = {}
    low = {}
    on_stack = set()
    stack = []
    sccs = []
    counter = [0]

    def strongconnect(root):
        work = [(root, iter(sorted(adj.get(root, ()))))]
        index[root] = low[root] = counter[0]
        counter[0] += 1
        stack.append(root)
        on_stack.add(root)
        while work:
            v, it = work[-1]
            advanced = False
            for w in it:
                if w not in index:
                    index[w] = low[w] = counter[0]
                    counter[0] += 1
                    stack.append(w)
                    on_stack.add(w)
                    work.append((w, iter(sorted(adj.get(w, ())))))
                    advanced = True
                    break
                elif w in on_stack:
                    low[v] = min(low[v], index[w])
            if advanced:
                continue
            if low[v] == index[v]:
                comp = []
                while True:
                    w = stack.pop()
                    on_stack.discard(w)
                    comp.append(w)
                    if w == v:
                        break
                sccs.append(sorted(comp))
            work.pop()
            if work:
                low[work[-1][0]] = min(low[work[-1][0]], low[v])

    for n in sorted(nodes):
        if n not in index:
            strongconnect(n)
    return sccs


def weak_components(edges):
    """Undirected connected components over the given directed edge set.

    Edge-induced: only vertices incident to an edge are considered.
    """
    parent = {}

    def find(x):
        parent.setdefault(x, x)
        root = x
        while parent[root] != root:
            root = parent[root]
        while parent[x] != root:
            parent[x], x = root, parent[x]
        return root

    def union(a, b):
        parent[find(a)] = find(b)

    for a, b in edges:
        union(a, b)
    groups = collections.defaultdict(int)
    for v in parent:
        groups[find(v)] += 1
    return sorted(groups.values(), reverse=True)


def _parser_selftest(cards_dir):
    """Guard against the first-item-drop regression: a known card must parse fully.

    `\\s*` after a key's colon would eat the first block-list item; this asserts a
    fixture card parses all items. Skips silently if the fixture isn't present.
    """
    p = os.path.join(cards_dir, "design-scale-erlang-otp", "alarm-handler.md")
    if not os.path.exists(p):
        return
    fm = front_matter(open(p, encoding="utf-8", errors="replace").read())
    expect = {
        "prerequisites": ["event-manager", "event-handler"],
        "extends": ["event-handler"],
        "related": ["notifying-events", "swapping-event-handlers"],
        "contrasts_with": [],
    }
    for k, want in expect.items():
        got = list_field(fm, k)
        if got != want:
            raise SystemExit(
                f"parser self-test FAILED for alarm-handler {k}: got {got!r}, want {want!r}"
            )


def compute(cards_dir):
    _parser_selftest(cards_dir)
    files = sorted(glob.glob(os.path.join(cards_dir, "**", "*.md"), recursive=True))
    if not files:
        raise SystemExit(f"no cards found under {cards_dir!r} — run `make fetch-cards` first")

    slug_sources = collections.defaultdict(set)   # slug -> {source_slug}
    # abstract assertions: per (x, y) -> set of types ; and per (x,y,type) -> book count
    pair_types = collections.defaultdict(set)
    triple_books = collections.Counter()
    typed_edges = collections.defaultdict(set)     # type -> {(x, y)}

    for f in files:
        rel = os.path.relpath(f, cards_dir)
        source = rel.split(os.sep)[0]
        text = open(f, encoding="utf-8", errors="replace").read()
        fm = front_matter(text)
        x = slug_of(fm, f)
        slug_sources[x].add(source)
        for k in REL_KEYS:
            for y in list_field(fm, k):
                pair_types[(x, y)].add(k)
                triple_books[(x, y, k)] += 1
                typed_edges[k].add((x, y))

    all_slugs = set(slug_sources)

    # --- abstract relation graph (union of all types) for degree centrality ---
    deg = collections.Counter()
    for (x, y) in pair_types:
        deg[x] += 1   # out
        deg[y] += 1   # in
    top_k = [[s, d] for s, d in sorted(deg.items(), key=lambda kv: (-kv[1], kv[0]))[:TOP_K]]

    # --- prerequisites projection: cyclic strong components ---
    prereq_adj = collections.defaultdict(set)
    prereq_nodes = set()
    for (x, y) in typed_edges["prerequisites"]:
        prereq_adj[x].add(y)
        prereq_nodes.add(x)
        prereq_nodes.add(y)
    sccs = tarjan_scc(prereq_adj, prereq_nodes)
    cyclic_sccs = sorted(
        [c for c in sccs if len(c) > 1 or (c[0] in prereq_adj.get(c[0], set()))]
    )

    # --- connectivity, two lenses ---
    # (a) related-only: clustered by explicit relatedness
    related_sizes = weak_components(sorted(typed_edges["related"]))
    # (b) all four relation types: clustered by any semantic link
    all_rel_edges = sorted(set().union(*[typed_edges[k] for k in REL_KEYS]))
    all_rel_sizes = weak_components(all_rel_edges)

    # --- duplicates / coverage ---
    multi_book = sorted(s for s, ss in slug_sources.items() if len(ss) > 1)
    five_book = sorted(s for s, ss in slug_sources.items() if len(ss) >= 5)

    # --- ghosts: referenced but no card ---
    referenced = set()
    for (x, y) in pair_types:
        referenced.add(x)
        referenced.add(y)
    ghosts = sorted(referenced - all_slugs)

    multi_typed = sorted(["%s -> %s" % p for p, ts in pair_types.items() if len(ts) > 1])
    multi_asserted = sorted(
        ["%s -[%s]-> %s" % (x, k, y) for (x, y, k), c in triple_books.items() if c > 1]
    )

    return {
        "sources": dict(sorted(
            collections.Counter(
                os.path.relpath(f, cards_dir).split(os.sep)[0] for f in files
            ).items()
        )),
        "n_source_vertices": len(files),
        "n_abstract_vertices": len(all_slugs),
        "n_multi_book_slugs": len(multi_book),
        "five_book_slugs": five_book,
        "abstract_edge_assertions_by_type": {k: len(typed_edges[k]) for k in REL_KEYS},
        "n_abstract_ordered_pairs": len(pair_types),
        "n_multi_typed_pairs": len(multi_typed),
        "n_multi_asserted_triples": len(multi_asserted),
        "prereq_nodes": len(prereq_nodes),
        "prereq_edges": len(typed_edges["prerequisites"]),
        "prereq_cyclic_strong_components": cyclic_sccs,
        "n_prereq_cycles": len(cyclic_sccs),
        "related_n_components": len(related_sizes),
        "related_component_sizes_top": related_sizes[:8],
        "related_giant_size": related_sizes[0] if related_sizes else 0,
        "all_relations_n_components": len(all_rel_sizes),
        "all_relations_component_sizes_top": all_rel_sizes[:8],
        "all_relations_giant_size": all_rel_sizes[0] if all_rel_sizes else 0,
        "top_k_by_total_degree": top_k,
        "ghost_concepts": ghosts,
    }


def main():
    args = [a for a in sys.argv[1:] if a != "--json"]
    cards = args[0] if args else DEFAULT_CARDS
    facts = compute(cards)
    print(json.dumps(facts, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
