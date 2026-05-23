-module(graffeo_builder).
-moduledoc """
The build-half behaviour: envelope-based constructors used by
constructive algorithms (`subgraph`, `condensation`).

Each backend implements these callbacks. A constructive algorithm
calls `Backend:empty_like(G)` then threads the result through
`Backend:build_add_vertex` and `Backend:build_add_edge`.

For the value backend each step returns a new envelope (pure).
For the handle backend each step mutates a fresh handle and returns
the same envelope. Algorithms that thread the returned graph work
correctly for both.

**Tier-2 lifecycle note:** constructive algorithms over a handle
graph create a **new** `digraph` handle the caller owns and must
`graffeo_digraph:delete/1`.
""".

-doc "A fresh, empty graph of the same backend as `G`.".
-callback empty_like(G :: graffeo:graph()) -> graffeo:graph().

-doc "Add a vertex with the default label (builder).".
-callback build_add_vertex(G :: graffeo:graph(), V :: graffeo:vertex()) ->
    graffeo:graph().

-doc "Add a vertex with a label (builder).".
-callback build_add_vertex(G :: graffeo:graph(), V :: graffeo:vertex(), Label :: graffeo:label()) ->
    graffeo:graph().

-doc "Add an edge with metadata (builder).".
-callback build_add_edge(
    G :: graffeo:graph(),
    From :: graffeo:vertex(),
    To :: graffeo:vertex(),
    Meta :: graffeo:edge_meta()
) ->
    graffeo:graph().
