-module(erlc_ingest).
-moduledoc """
Builds the two-layer graffeo graph from parsed concept cards.

Source layer: `{SourceSlug, Slug}` vertices with local relation edges.
Abstract layer: `Slug` vertices with derived relation edges.
Membership: `{SourceSlug, Slug} -> Slug` (`instance_of`).
""".

-export([
    build/1,
    build_from_dir/1,
    source_vertices/1,
    abstract_vertices/1
]).

-export_type([result/0]).

-type result() :: #{
    graph := graffeo:graph(),
    source_count := non_neg_integer(),
    abstract_count := non_neg_integer()
}.

-doc "Build the two-layer graph from a sorted list of parsed cards.".
-spec build([erlc_parser:card()]) -> result().
build(Cards) ->
    Sorted = lists:sort(
        fun(A, B) ->
            maps:get(slug, A) =< maps:get(slug, B)
        end,
        Cards
    ),
    G0 = graffeo:new(),
    G1 = add_source_layer(Sorted, G0),
    G2 = add_abstract_layer(Sorted, G1),
    G3 = add_membership(Sorted, G2),
    G4 = add_source_edges(Sorted, G3),
    G5 = add_abstract_edges(Sorted, G4),
    #{
        graph => G5,
        source_count => length(Sorted),
        abstract_count => length(
            lists:usort(
                [maps:get(slug, C) || C <- Sorted]
            )
        )
    }.

-doc "Build the graph from the concept cards directory tree.".
-spec build_from_dir(file:filename_all()) -> result().
build_from_dir(BaseDir) ->
    Dirs = filelib:wildcard(BaseDir ++ "/*"),
    Files = lists:sort(
        lists:flatmap(
            fun(Dir) ->
                filelib:wildcard(Dir ++ "/*.md")
            end,
            Dirs
        )
    ),
    Cards = lists:map(
        fun(F) ->
            {ok, C} = erlc_parser:parse_file(F),
            C
        end,
        Files
    ),
    build(Cards).

-spec add_source_layer([erlc_parser:card()], graffeo:graph()) -> graffeo:graph().
add_source_layer(Cards, G) ->
    lists:foldl(
        fun(Card, Acc) ->
            V = source_vertex(Card),
            graffeo:add_vertex(Acc, V)
        end,
        G,
        Cards
    ).

-spec add_abstract_layer([erlc_parser:card()], graffeo:graph()) -> graffeo:graph().
add_abstract_layer(Cards, G) ->
    Slugs = lists:usort([maps:get(slug, C) || C <- Cards]),
    lists:foldl(
        fun(Slug, Acc) ->
            graffeo:add_vertex(Acc, Slug)
        end,
        G,
        Slugs
    ).

-spec add_membership([erlc_parser:card()], graffeo:graph()) -> graffeo:graph().
add_membership(Cards, G) ->
    lists:foldl(
        fun(Card, Acc) ->
            From = source_vertex(Card),
            To = maps:get(slug, Card),
            graffeo:add_edge(Acc, From, To, #{label => instance_of})
        end,
        G,
        Cards
    ).

-spec add_source_edges([erlc_parser:card()], graffeo:graph()) -> graffeo:graph().
add_source_edges(Cards, G) ->
    CardsBySource = group_by_source(Cards),
    maps:fold(
        fun(Src, SrcCards, GAcc) ->
            AllSlugs = sets:from_list(
                [maps:get(slug, C) || C <- SrcCards], [{version, 2}]
            ),
            lists:foldl(
                fun(Card, GAcc2) ->
                    add_card_source_edges(Src, Card, AllSlugs, GAcc2)
                end,
                GAcc,
                SrcCards
            )
        end,
        G,
        CardsBySource
    ).

-spec add_card_source_edges(
    binary(),
    erlc_parser:card(),
    sets:set(binary()),
    graffeo:graph()
) -> graffeo:graph().
add_card_source_edges(Src, Card, AllSlugs, G) ->
    FromSlug = maps:get(slug, Card),
    From = {Src, FromSlug},
    RelTypes = [
        {prerequisites, maps:get(prerequisites, Card)},
        {extends, maps:get(extends, Card)},
        {related, maps:get(related, Card)},
        {contrasts_with, maps:get(contrasts_with, Card)}
    ],
    lists:foldl(
        fun({Type, Targets}, GAcc) ->
            SortedTargets = lists:sort(Targets),
            lists:foldl(
                fun(TargetSlug, GAcc2) ->
                    case sets:is_element(TargetSlug, AllSlugs) of
                        true ->
                            To = {Src, TargetSlug},
                            add_typed_edge(GAcc2, From, To, Type, Src);
                        false ->
                            GAcc2
                    end
                end,
                GAcc,
                SortedTargets
            )
        end,
        G,
        RelTypes
    ).

-spec add_abstract_edges([erlc_parser:card()], graffeo:graph()) -> graffeo:graph().
add_abstract_edges(Cards, G) ->
    G1 = project_source_edges(G),
    add_cross_only_edges(Cards, G1).

-spec project_source_edges(graffeo:graph()) -> graffeo:graph().
project_source_edges(G) ->
    SrcVs = source_vertices(G),
    lists:foldl(
        fun({Src, FromSlug} = From, GAcc) ->
            OutNbrs = graffeo:out_neighbours(G, From),
            SrcNbrs = [{S, T} || {S, T} <- OutNbrs, S =:= Src],
            lists:foldl(
                fun({_, ToSlug}, GAcc2) ->
                    case graffeo:edge_meta(G, From, {Src, ToSlug}) of
                        {ok, #{label := #{types := Types, asserted_by := Asserters}}} ->
                            project_one_edge(GAcc2, FromSlug, ToSlug, Types, Asserters);
                        _ ->
                            GAcc2
                    end
                end,
                GAcc,
                SrcNbrs
            )
        end,
        G,
        SrcVs
    ).

-spec project_one_edge(
    graffeo:graph(),
    binary(),
    binary(),
    [atom()],
    [binary()]
) -> graffeo:graph().
project_one_edge(G, FromSlug, ToSlug, Types, Asserters) ->
    case graffeo:edge_meta(G, FromSlug, ToSlug) of
        {ok, #{label := #{types := ExTypes, asserted_by := ExAsserters}}} ->
            NewTypes = lists:usort(Types ++ ExTypes),
            NewAsserters = lists:usort(Asserters ++ ExAsserters),
            Meta = #{
                label => #{
                    types => NewTypes,
                    asserted_by => NewAsserters
                }
            },
            graffeo:add_edge(G, FromSlug, ToSlug, Meta);
        error ->
            Meta = #{label => #{types => Types, asserted_by => Asserters}},
            graffeo:add_edge(G, FromSlug, ToSlug, Meta)
    end.

-spec add_cross_only_edges([erlc_parser:card()], graffeo:graph()) ->
    graffeo:graph().
add_cross_only_edges(Cards, G) ->
    CardsBySource = group_by_source(Cards),
    AllCardSlugs = sets:from_list(
        [maps:get(slug, C) || C <- Cards], [{version, 2}]
    ),
    lists:foldl(
        fun(Card, GAcc) ->
            Src = maps:get(source_slug, Card),
            SrcCards = maps:get(Src, CardsBySource),
            LocalSlugs = sets:from_list(
                [maps:get(slug, C) || C <- SrcCards], [{version, 2}]
            ),
            add_card_cross_edges(Card, LocalSlugs, AllCardSlugs, GAcc)
        end,
        G,
        Cards
    ).

-spec add_card_cross_edges(
    erlc_parser:card(),
    sets:set(binary()),
    sets:set(binary()),
    graffeo:graph()
) ->
    graffeo:graph().
add_card_cross_edges(Card, LocalSlugs, AllCardSlugs, G) ->
    FromSlug = maps:get(slug, Card),
    Src = maps:get(source_slug, Card),
    RelTypes = [
        {prerequisites, maps:get(prerequisites, Card)},
        {extends, maps:get(extends, Card)},
        {related, maps:get(related, Card)},
        {contrasts_with, maps:get(contrasts_with, Card)}
    ],
    lists:foldl(
        fun({Type, Targets}, GAcc) ->
            SortedTargets = lists:sort(Targets),
            lists:foldl(
                fun(TargetSlug, GAcc2) ->
                    IsLocal = sets:is_element(TargetSlug, LocalSlugs),
                    IsSelf = TargetSlug =:= FromSlug,
                    case IsSelf orelse IsLocal of
                        true ->
                            GAcc2;
                        false ->
                            case sets:is_element(TargetSlug, AllCardSlugs) of
                                true ->
                                    add_typed_edge(
                                        GAcc2,
                                        FromSlug,
                                        TargetSlug,
                                        Type,
                                        Src
                                    );
                                false ->
                                    ensure_ghost_vertex(
                                        GAcc2,
                                        TargetSlug,
                                        FromSlug,
                                        Type,
                                        Src
                                    )
                            end
                    end
                end,
                GAcc,
                SortedTargets
            )
        end,
        G,
        RelTypes
    ).

-spec ensure_ghost_vertex(
    graffeo:graph(),
    binary(),
    binary(),
    atom(),
    binary()
) -> graffeo:graph().
ensure_ghost_vertex(G, TargetSlug, FromSlug, Type, Src) ->
    G1 =
        case lists:member(TargetSlug, graffeo:vertices(G)) of
            true -> G;
            false -> graffeo:add_vertex(G, TargetSlug)
        end,
    add_typed_edge(G1, FromSlug, TargetSlug, Type, Src).

-spec add_typed_edge(
    graffeo:graph(),
    graffeo:vertex(),
    graffeo:vertex(),
    atom(),
    binary()
) -> graffeo:graph().
add_typed_edge(G, From, To, Type, Src) ->
    case graffeo:edge_meta(G, From, To) of
        {ok, #{label := #{types := Types, asserted_by := AssertedBy}}} ->
            NewTypes = lists:usort([Type | Types]),
            NewAsserted = lists:usort([Src | AssertedBy]),
            Meta = #{
                label => #{
                    types => NewTypes,
                    asserted_by => NewAsserted
                }
            },
            graffeo:add_edge(G, From, To, Meta);
        error ->
            Meta = #{label => #{types => [Type], asserted_by => [Src]}},
            graffeo:add_edge(G, From, To, Meta)
    end.

-spec source_vertex(erlc_parser:card()) -> {binary(), binary()}.
source_vertex(Card) ->
    {maps:get(source_slug, Card), maps:get(slug, Card)}.

-spec group_by_source([erlc_parser:card()]) -> #{binary() => [erlc_parser:card()]}.
group_by_source(Cards) ->
    lists:foldl(
        fun(Card, Acc) ->
            Src = maps:get(source_slug, Card),
            maps:update_with(
                Src,
                fun(Existing) -> Existing ++ [Card] end,
                [Card],
                Acc
            )
        end,
        #{},
        Cards
    ).

-doc "Extract source-layer vertices from a built graph.".
-spec source_vertices(graffeo:graph()) -> [graffeo:vertex()].
source_vertices(G) ->
    [V || V <- graffeo:vertices(G), is_tuple(V)].

-doc "Extract abstract-layer vertices from a built graph.".
-spec abstract_vertices(graffeo:graph()) -> [graffeo:vertex()].
abstract_vertices(G) ->
    [V || V <- graffeo:vertices(G), is_binary(V)].
