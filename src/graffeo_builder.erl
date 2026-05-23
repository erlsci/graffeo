-module(graffeo_builder).
-moduledoc """
The build-half behaviour: constructors and mutators each backend
implements in its native idiom.

A Tier-1 (value) backend returns a new ref from every operation.
A Tier-2 (handle) backend mutates in place and returns `ok`.
""".

-doc "Create a new, empty graph ref.".
-callback new() -> Ref :: term().

-doc "Add a vertex with the default label.".
-callback add_vertex(Ref :: term(), V :: graffeo:vertex()) ->
    term().

-doc "Add a vertex with a label.".
-callback add_vertex(Ref :: term(), V :: graffeo:vertex(), Label :: graffeo:label()) ->
    term().

-doc "Add an edge with default metadata.".
-callback add_edge(Ref :: term(), From :: graffeo:vertex(), To :: graffeo:vertex()) ->
    term().

-doc "Add an edge with metadata (weight, label).".
-callback add_edge(
    Ref :: term(),
    From :: graffeo:vertex(),
    To :: graffeo:vertex(),
    Meta :: graffeo:edge_meta()
) ->
    term().
