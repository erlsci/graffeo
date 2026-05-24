-module(erlc_parser_tests).
-include_lib("eunit/include/eunit.hrl").

section_header_format_test() ->
    Bin = <<
        "---\n"
        "# === CORE IDENTIFICATION ===\n"
        "concept: gen_server Behaviour\n"
        "slug: gen-server\n"
        "\n"
        "# === CLASSIFICATION ===\n"
        "category: otp-behaviours\n"
        "tier: intermediate\n"
        "\n"
        "# === PROVENANCE ===\n"
        "source: Programming Erlang\n"
        "source_slug: programming-erlang\n"
        "\n"
        "# === TYPED RELATIONSHIPS ===\n"
        "prerequisites:\n"
        "  - generic-server\n"
        "  - behaviour\n"
        "extends:\n"
        "  - generic-server\n"
        "related:\n"
        "  - gen-server-callbacks\n"
        "  - supervisor\n"
        "contrasts_with:\n"
        "  - gen-event\n"
        "---\n"
        "\n# Body text\n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    ?assertEqual(<<"gen-server">>, maps:get(slug, Card)),
    ?assertEqual(<<"gen_server Behaviour">>, maps:get(concept, Card)),
    ?assertEqual(<<"otp-behaviours">>, maps:get(category, Card)),
    ?assertEqual(<<"intermediate">>, maps:get(tier, Card)),
    ?assertEqual(<<"Programming Erlang">>, maps:get(source, Card)),
    ?assertEqual(<<"programming-erlang">>, maps:get(source_slug, Card)),
    ?assertEqual(
        [<<"generic-server">>, <<"behaviour">>],
        maps:get(prerequisites, Card)
    ),
    ?assertEqual([<<"generic-server">>], maps:get(extends, Card)),
    ?assertEqual(
        [<<"gen-server-callbacks">>, <<"supervisor">>],
        maps:get(related, Card)
    ),
    ?assertEqual([<<"gen-event">>], maps:get(contrasts_with, Card)).

flat_format_test() ->
    Bin = <<
        "---\n"
        "concept: Allocation Strategy\n"
        "slug: allocation-strategy\n"
        "category: performance\n"
        "tier: advanced\n"
        "source: Erlang in Anger\n"
        "source_slug: erlang-in-anger\n"
        "prerequisites:\n"
        "  - erlang-memory-model\n"
        "related:\n"
        "  - memory-fragmentation\n"
        "contrasts_with: []\n"
        "---\n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    ?assertEqual(<<"allocation-strategy">>, maps:get(slug, Card)),
    ?assertEqual(<<"advanced">>, maps:get(tier, Card)),
    ?assertEqual([<<"erlang-memory-model">>], maps:get(prerequisites, Card)),
    ?assertEqual([], maps:get(extends, Card)),
    ?assertEqual([], maps:get(contrasts_with, Card)).

empty_inline_list_test() ->
    Bin = <<
        "---\n"
        "concept: Test\n"
        "slug: test-card\n"
        "category: testing\n"
        "tier: basic\n"
        "source: Test Book\n"
        "source_slug: test-book\n"
        "prerequisites: []\n"
        "extends: []\n"
        "related: []\n"
        "contrasts_with: []\n"
        "---\n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    ?assertEqual([], maps:get(prerequisites, Card)),
    ?assertEqual([], maps:get(extends, Card)),
    ?assertEqual([], maps:get(related, Card)),
    ?assertEqual([], maps:get(contrasts_with, Card)).

missing_extends_key_test() ->
    Bin = <<
        "---\n"
        "concept: Atom Leak\n"
        "slug: atom-leak\n"
        "category: debugging\n"
        "tier: intermediate\n"
        "source: Erlang in Anger\n"
        "source_slug: erlang-in-anger\n"
        "prerequisites:\n"
        "  - atom-table\n"
        "related:\n"
        "  - recon-info\n"
        "contrasts_with: []\n"
        "---\n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    ?assertEqual([], maps:get(extends, Card)).

quoted_values_test() ->
    Bin = <<
        "---\n"
        "concept: Driver\n"
        "slug: driver\n"
        "category: performance\n"
        "tier: advanced\n"
        "source: \"ERTS User's Guide\"\n"
        "source_slug: otp-erts\n"
        "prerequisites:\n"
        "  - erlang-process\n"
        "  - erlang-ports\n"
        "extends: []\n"
        "related:\n"
        "  - erl-nif\n"
        "contrasts_with:\n"
        "  - erl-nif\n"
        "---\n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    ?assertEqual(<<"ERTS User's Guide">>, maps:get(source, Card)),
    ?assertEqual(
        [<<"erlang-process">>, <<"erlang-ports">>],
        maps:get(prerequisites, Card)
    ).

ghost_reference_test() ->
    Bin = <<
        "---\n"
        "concept: Driver\n"
        "slug: driver\n"
        "category: performance\n"
        "tier: advanced\n"
        "source: ERTS Guide\n"
        "source_slug: otp-erts\n"
        "prerequisites:\n"
        "  - erlang-process\n"
        "  - erlang-ports\n"
        "extends: []\n"
        "related:\n"
        "  - erl-nif\n"
        "contrasts_with: []\n"
        "---\n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    Prereqs = maps:get(prerequisites, Card),
    ?assert(lists:member(<<"erlang-ports">>, Prereqs)).

missing_required_field_test() ->
    Bin = <<
        "---\n"
        "concept: Incomplete\n"
        "category: testing\n"
        "---\n"
    >>,
    {error, {missing_field, <<"slug">>}} = erlc_parser:parse_string(Bin).

no_opening_delimiter_test() ->
    Bin = <<"concept: Broken\nslug: broken\n">>,
    {error, no_opening_delimiter} = erlc_parser:parse_string(Bin).

read_nonexistent_file_test() ->
    {error, {read_failed, "/nonexistent/path.md", enoent}} =
        erlc_parser:parse_file("/nonexistent/path.md").

no_closing_delimiter_test() ->
    Bin = <<"---\nconcept: Broken\nslug: broken\n">>,
    {error, {no_closing_delimiter, _}} = erlc_parser:parse_string(Bin).

trailing_delimiter_chars_test() ->
    Bin = <<
        "--- \nconcept: Test\nslug: test\ncategory: cat\n"
        "tier: basic\nsource: Book\nsource_slug: book\n--- \n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    ?assertEqual(<<"test">>, maps:get(slug, Card)).

list_item_before_key_test() ->
    Bin = <<
        "---\n"
        "  - orphan-item\n"
        "concept: Test\n"
        "slug: test\n"
        "category: cat\n"
        "tier: basic\n"
        "source: Book\n"
        "source_slug: book\n"
        "---\n"
    >>,
    {ok, _} = erlc_parser:parse_string(Bin).

indented_list_items_test() ->
    Bin = <<
        "---\n"
        "concept: Test\n"
        "slug: test\n"
        "category: cat\n"
        "tier: basic\n"
        "source: Book\n"
        "source_slug: book\n"
        "prerequisites:\n"
        "  - alpha\n"
        "  - beta\n"
        "---\n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    ?assertEqual([<<"alpha">>, <<"beta">>], maps:get(prerequisites, Card)).

bare_key_colon_test() ->
    Bin = <<
        "---\n"
        "concept: Test\n"
        "slug: test\n"
        "category: cat\n"
        "tier: basic\n"
        "source: Book\n"
        "source_slug: book\n"
        "prereq_unknown_format\n"
        "---\n"
    >>,
    {ok, _} = erlc_parser:parse_string(Bin).

scalar_then_list_item_test() ->
    Bin = <<
        "---\n"
        "concept: Test\n"
        "slug: test\n"
        "category: cat\n"
        "tier: basic\n"
        "source: Book\n"
        "source_slug: book\n"
        "prerequisites: inline-value\n"
        "  - actual-item\n"
        "---\n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    ?assertEqual([<<"actual-item">>], maps:get(prerequisites, Card)).

list_valued_scalar_field_test() ->
    Bin = <<
        "---\n"
        "concept: Test\n"
        "slug:\n"
        "  - multi\n"
        "  - valued\n"
        "category: cat\n"
        "tier: basic\n"
        "source: Book\n"
        "source_slug: book\n"
        "---\n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    ?assertEqual(<<"multi, valued">>, maps:get(slug, Card)).

single_binary_as_list_test() ->
    Bin = <<
        "---\n"
        "concept: Test\n"
        "slug: test\n"
        "category: cat\n"
        "tier: basic\n"
        "source: Book\n"
        "source_slug: book\n"
        "prerequisites: solo-item\n"
        "---\n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    ?assertEqual([<<"solo-item">>], maps:get(prerequisites, Card)).

unquote_partial_test() ->
    Bin = <<
        "---\n"
        "concept: \"Half quoted\n"
        "slug: test\n"
        "category: cat\n"
        "tier: basic\n"
        "source: Book\n"
        "source_slug: book\n"
        "---\n"
    >>,
    {ok, Card} = erlc_parser:parse_string(Bin),
    ?assertEqual(<<"Half quoted">>, maps:get(concept, Card)).

real_card_file_test() ->
    Path =
        "../../workbench/ai-engineering/knowledge/erlang/concept-cards"
        "/programming-erlang/gen-server.md",
    case filelib:is_file(Path) of
        true ->
            {ok, Card} = erlc_parser:parse_file(Path),
            ?assertEqual(<<"gen-server">>, maps:get(slug, Card)),
            ?assertEqual(<<"programming-erlang">>, maps:get(source_slug, Card)),
            ?assert(length(maps:get(prerequisites, Card)) >= 3),
            ?assert(length(maps:get(related, Card)) >= 4);
        false ->
            ok
    end.

all_cards_parse_test_() ->
    {timeout, 120, fun() ->
        Base = "../../workbench/ai-engineering/knowledge/erlang/concept-cards",
        Dirs = filelib:wildcard(Base ++ "/*"),
        Files = lists:flatmap(
            fun(Dir) ->
                filelib:wildcard(Dir ++ "/*.md")
            end,
            Dirs
        ),
        ?assert(length(Files) >= 1600),
        Errors = lists:filtermap(
            fun(F) ->
                case erlc_parser:parse_file(F) of
                    {ok, _} -> false;
                    {error, R} -> {true, {F, R}}
                end
            end,
            Files
        ),
        ?assertEqual([], Errors)
    end}.
