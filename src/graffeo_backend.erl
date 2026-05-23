-module(graffeo_backend).
-moduledoc """
The read-half behaviour: the universal accessor contract that every
backend implements and every algorithm consumes.

Seven callbacks covering the full read surface from `digraph_utils`
plus `out_degree/2` for the degree layer (R7).
""".

-doc "All vertices in the graph.".
-callback vertices(Ref :: term()) -> [graffeo:vertex()].

-doc "Vertices reachable from `V` via outgoing edges.".
-callback out_neighbours(Ref :: term(), V :: graffeo:vertex()) ->
    [graffeo:vertex()].

-doc "Vertices that reach `V` via incoming edges.".
-callback in_neighbours(Ref :: term(), V :: graffeo:vertex()) ->
    [graffeo:vertex()].

-doc "Number of incoming edges to `V`.".
-callback in_degree(Ref :: term(), V :: graffeo:vertex()) ->
    non_neg_integer().

-doc "Number of outgoing edges from `V`.".
-callback out_degree(Ref :: term(), V :: graffeo:vertex()) ->
    non_neg_integer().

-doc "Total number of edges in the graph.".
-callback no_edges(Ref :: term()) -> non_neg_integer().

-doc "Total number of vertices in the graph.".
-callback no_vertices(Ref :: term()) -> non_neg_integer().

-doc "Metadata for the edge from `From` to `To`.".
-callback edge_meta(Ref :: term(), From :: graffeo:vertex(), To :: graffeo:vertex()) ->
    {ok, graffeo:edge_meta()} | error.

-doc "Label of vertex `V`.".
-callback vertex_label(Ref :: term(), V :: graffeo:vertex()) ->
    {ok, graffeo:label()} | error.
