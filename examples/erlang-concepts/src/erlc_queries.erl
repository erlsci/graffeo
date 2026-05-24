-module(erlc_queries).
-moduledoc "Query catalog for the erlang-concepts worked example.".

-export([
    prerequisite_cycles/1,
    learning_order/1,
    related_components/1,
    semantic_components/1,
    top_concepts_by_degree/2,
    coverage_breadth/1,
    ghost_concepts/1,
    related_cheap/3,
    related_extended/3
]).

-doc """
Find cycles in the abstract prerequisite graph.
Returns `{IsCyclic, Cycles}` where Cycles is the list of cyclic
strongly connected components (each with length > 1).
""".
-spec prerequisite_cycles(graffeo:graph()) ->
    {boolean(), [[binary()]]}.
prerequisite_cycles(G) ->
    PG = project_by_type(G, prerequisites),
    IsCyclic = not graffeo:is_acyclic(PG),
    CSCs = graffeo:cyclic_strong_components(PG),
    Cycles = [lists:sort(C) || C = [_, _ | _] <- CSCs],
    {IsCyclic, lists:sort(Cycles)}.

-doc """
Compute a learning order by condensing cycles in the prerequisite graph.
Returns `{ok, Order}` on success, or `false` if topsort still fails.
""".
-spec learning_order(graffeo:graph()) ->
    {ok, [graffeo:vertex()]} | false.
learning_order(G) ->
    PG = project_by_type(G, prerequisites),
    Condensed = graffeo:condensation(PG),
    graffeo:topsort(Condensed).

-doc """
Find connected components in the abstract `related` projection.
Returns `{ComponentCount, GiantSize, Components}`.
""".
-spec related_components(graffeo:graph()) ->
    {non_neg_integer(), non_neg_integer(), [[binary()]]}.
related_components(G) ->
    RG = project_by_type(G, related),
    Components = graffeo:components(RG),
    Sorted = lists:sort(fun(A, B) -> length(A) >= length(B) end, Components),
    GiantSize =
        case Sorted of
            [Giant | _] -> length(Giant);
            [] -> 0
        end,
    {length(Components), GiantSize, Sorted}.

-doc """
Semantic connectivity: components over the union of all four relation types.
Returns `{ComponentCount, GiantSize, Components}`.
""".
-spec semantic_components(graffeo:graph()) ->
    {non_neg_integer(), non_neg_integer(), [[binary()]]}.
semantic_components(G) ->
    AG = project_abstract_relations(G),
    Components = graffeo:components(AG),
    Sorted = lists:sort(fun(A, B) -> length(A) >= length(B) end, Components),
    GiantSize =
        case Sorted of
            [Giant | _] -> length(Giant);
            [] -> 0
        end,
    {length(Components), GiantSize, Sorted}.

-doc "Top-k concepts by total degree on the abstract relation projection.".
-spec top_concepts_by_degree(graffeo:graph(), pos_integer()) ->
    [{binary(), non_neg_integer()}].
top_concepts_by_degree(G, K) ->
    AG = project_abstract_relations(G),
    graffeo:top_k_by_degree(AG, K).

-doc """
Coverage breadth: how many sources cover each concept.
Returns the concepts sorted by source count descending.
""".
-spec coverage_breadth(graffeo:graph()) ->
    [{binary(), non_neg_integer()}].
coverage_breadth(G) ->
    AbsVs = erlc_ingest:abstract_vertices(G),
    Counts = lists:filtermap(
        fun(Slug) ->
            InNbrs = graffeo:in_neighbours(G, Slug),
            case [S || {S, _} <- InNbrs] of
                [] -> false;
                Sources -> {true, {Slug, length(Sources)}}
            end
        end,
        AbsVs
    ),
    lists:sort(fun({_, A}, {_, B}) -> A >= B end, Counts).

-doc "Find ghost concepts: abstract vertices with no membership edges.".
-spec ghost_concepts(graffeo:graph()) -> [binary()].
ghost_concepts(G) ->
    AbsVs = erlc_ingest:abstract_vertices(G),
    lists:sort(
        lists:filter(
            fun(Slug) ->
                InNbrs = graffeo:in_neighbours(G, Slug),
                not lists:any(fun is_tuple/1, InNbrs)
            end,
            AbsVs
        )
    ).

-doc "Cheap/local relatedness: source-local `related` neighbours within one book.".
-spec related_cheap(graffeo:graph(), binary(), binary()) -> [binary()].
related_cheap(G, SourceSlug, ConceptSlug) ->
    SrcV = {SourceSlug, ConceptSlug},
    Nbrs = graffeo:out_neighbours(G, SrcV),
    SrcNbrs = [{S, T} || {S, T} <- Nbrs, S =:= SourceSlug],
    lists:usort(
        lists:filtermap(
            fun({_, TargetSlug}) ->
                case graffeo:edge_meta(G, SrcV, {SourceSlug, TargetSlug}) of
                    {ok, #{label := #{types := Types}}} ->
                        case lists:member(related, Types) of
                            true -> {true, TargetSlug};
                            false -> false
                        end;
                    _ ->
                        false
                end
            end,
            SrcNbrs
        )
    ).

-doc """
Extended relatedness: local related + sibling cards' related neighbours.
Goes up via membership to the concept, down to sibling cards in other
books, then collects their local `related` neighbours.
""".
-spec related_extended(graffeo:graph(), binary(), binary()) -> [binary()].
related_extended(G, SourceSlug, ConceptSlug) ->
    Local = related_cheap(G, SourceSlug, ConceptSlug),
    InNbrs = graffeo:in_neighbours(G, ConceptSlug),
    SiblingCards = [
        {S, T}
     || {S, T} <- InNbrs,
        S =/= SourceSlug,
        T =:= ConceptSlug
    ],
    SiblingRelated = lists:flatmap(
        fun({SibSrc, _}) ->
            related_cheap(G, SibSrc, ConceptSlug)
        end,
        SiblingCards
    ),
    lists:usort(Local ++ SiblingRelated).

%% --- Internal: projection helpers via graffeo:filter_edges/2 ---

-spec project_by_type(graffeo:graph(), atom()) -> graffeo:graph().
project_by_type(G, Type) ->
    graffeo:filter_edges(G, fun(From, To, Meta) ->
        is_binary(From) andalso is_binary(To) andalso
            has_type(Meta, Type)
    end).

-spec project_abstract_relations(graffeo:graph()) -> graffeo:graph().
project_abstract_relations(G) ->
    graffeo:filter_edges(G, fun(From, To, _Meta) ->
        is_binary(From) andalso is_binary(To)
    end).

-spec has_type(graffeo:edge_meta(), atom()) -> boolean().
has_type(#{label := #{types := Types}}, Type) ->
    lists:member(Type, Types);
has_type(_, _) ->
    false.
