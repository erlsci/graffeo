-module(erlc).
-moduledoc "Runner for the erlang-concepts worked example.".

-export([main/1]).

-doc "Run the erlang-concepts query catalog and print results.".
-spec main([string()]) -> ok.
main(_Args) ->
    Base = cards_dir(),
    io:format("=== Erlang Concepts Knowledge Graph ===~n~n"),
    io:format("Building graph from ~s ...~n", [Base]),
    Result = erlc_ingest:build_from_dir(Base),
    G = maps:get(graph, Result),
    print_summary(G, Result),
    print_prerequisite_cycles(G),
    print_learning_order(G),
    print_related_components(G),
    print_semantic_components(G),
    print_top_concepts(G),
    print_coverage_breadth(G),
    print_ghost_concepts(G),
    print_tunable_relatedness(G),
    ok.

-spec cards_dir() -> nonempty_string().
cards_dir() ->
    "../../workbench/ai-engineering/knowledge/erlang/concept-cards".

-spec print_summary(graffeo:graph(), erlc_ingest:result()) -> ok.
print_summary(G, Result) ->
    SrcVs = erlc_ingest:source_vertices(G),
    AbsVs = erlc_ingest:abstract_vertices(G),
    io:format("~nSource vertices: ~p~n", [length(SrcVs)]),
    io:format("Abstract vertices: ~p~n", [length(AbsVs)]),
    io:format("Total vertices: ~p~n", [graffeo:no_vertices(G)]),
    io:format("Total edges: ~p~n", [graffeo:no_edges(G)]),
    io:format(
        "Source count (from build): ~p~n",
        [maps:get(source_count, Result)]
    ),
    io:format(
        "Abstract count (from build): ~p~n~n",
        [maps:get(abstract_count, Result)]
    ).

-spec print_prerequisite_cycles(graffeo:graph()) -> ok.
print_prerequisite_cycles(G) ->
    io:format("=== Prerequisite Cycles ===~n"),
    {IsCyclic, Cycles} = erlc_queries:prerequisite_cycles(G),
    io:format("Abstract prerequisites acyclic: ~p~n", [not IsCyclic]),
    io:format("Cyclic SCCs (size > 1): ~p~n", [length(Cycles)]),
    lists:foreach(
        fun(C) ->
            io:format("  ~p~n", [C])
        end,
        Cycles
    ),
    io:format("~n").

-spec print_learning_order(graffeo:graph()) -> ok.
print_learning_order(G) ->
    io:format("=== Learning Order ===~n"),
    case erlc_queries:learning_order(G) of
        {ok, Order} ->
            io:format(
                "Condensation + topsort succeeded: ~p elements~n",
                [length(Order)]
            );
        false ->
            io:format("Topsort failed on condensed graph~n")
    end,
    io:format("~n").

-spec print_related_components(graffeo:graph()) -> ok.
print_related_components(G) ->
    io:format("=== Related Components ===~n"),
    {CompCount, GiantSize, _Comps} = erlc_queries:related_components(G),
    io:format("Components: ~p~n", [CompCount]),
    io:format("Giant component size: ~p~n~n", [GiantSize]).

-spec print_semantic_components(graffeo:graph()) -> ok.
print_semantic_components(G) ->
    io:format("=== Semantic Components (all types) ===~n"),
    {CompCount, GiantSize, _Comps} = erlc_queries:semantic_components(G),
    io:format("Components: ~p~n", [CompCount]),
    io:format("Giant component size: ~p~n~n", [GiantSize]).

-spec print_top_concepts(graffeo:graph()) -> ok.
print_top_concepts(G) ->
    io:format("=== Top Concepts by Degree ===~n"),
    TopK = erlc_queries:top_concepts_by_degree(G, 10),
    lists:foreach(
        fun({Slug, Deg}) ->
            io:format("  ~s: ~p~n", [Slug, Deg])
        end,
        TopK
    ),
    io:format("~n").

-spec print_coverage_breadth(graffeo:graph()) -> ok.
print_coverage_breadth(G) ->
    io:format("=== Coverage Breadth (5-book concepts) ===~n"),
    CB = erlc_queries:coverage_breadth(G),
    FiveBook = [{S, N} || {S, N} <- CB, N >= 5],
    lists:foreach(
        fun({Slug, N}) ->
            io:format("  ~s: ~p books~n", [Slug, N])
        end,
        FiveBook
    ),
    io:format("~n").

-spec print_ghost_concepts(graffeo:graph()) -> ok.
print_ghost_concepts(G) ->
    io:format("=== Ghost Concepts ===~n"),
    Ghosts = erlc_queries:ghost_concepts(G),
    io:format("Count: ~p~n", [length(Ghosts)]),
    lists:foreach(
        fun(Slug) ->
            io:format("  ~s~n", [Slug])
        end,
        Ghosts
    ),
    io:format("~n").

-spec print_tunable_relatedness(graffeo:graph()) -> ok.
print_tunable_relatedness(G) ->
    io:format("=== Tunable Relatedness (gen-server) ===~n"),
    Local = erlc_queries:related_cheap(
        G,
        <<"programming-erlang">>,
        <<"gen-server">>
    ),
    Extended = erlc_queries:related_extended(
        G,
        <<"programming-erlang">>,
        <<"gen-server">>
    ),
    io:format(
        "Cheap/local (programming-erlang): ~p concepts~n",
        [length(Local)]
    ),
    io:format("  ~p~n", [Local]),
    io:format("Extended (all books): ~p concepts~n", [length(Extended)]),
    io:format("  ~p~n", [Extended]),
    IsSuperset = lists:all(fun(X) -> lists:member(X, Extended) end, Local),
    io:format("Extended >= local: ~p~n~n", [IsSuperset]).
