-module(erlc_parser).
-moduledoc """
Tolerant front-matter parser for the erlang concept cards.

Handles two dialect variants: cards with `# === SECTION ===` comment
headers interleaved with key-value lines, and cards with flat
key-value front matter. Both use `---` delimiters.
""".

-export([parse_file/1, parse_string/1]).

-export_type([card/0]).

-doc "Parsed concept card with slug, provenance, and typed relationships.".
-type card() :: #{
    slug := binary(),
    concept := binary(),
    category := binary(),
    tier := binary(),
    source := binary(),
    source_slug := binary(),
    prerequisites := [binary()],
    extends := [binary()],
    related := [binary()],
    contrasts_with := [binary()]
}.

-doc "Parse a concept card file and return its structured front matter.".
-spec parse_file(file:filename_all()) ->
    {ok, card()}
    | {error,
        no_opening_delimiter
        | {no_closing_delimiter, non_neg_integer()}
        | {missing_field, binary()}
        | {read_failed, file:filename_all(), file:posix()}}.
parse_file(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> parse_string(Bin);
        {error, Reason} -> {error, {read_failed, Path, Reason}}
    end.

-doc "Parse a concept card from a binary string.".
-spec parse_string(binary()) ->
    {ok, card()}
    | {error,
        no_opening_delimiter
        | {no_closing_delimiter, non_neg_integer()}
        | {missing_field, binary()}}.
parse_string(Bin) ->
    Lines = binary:split(Bin, <<"\n">>, [global]),
    case extract_frontmatter(Lines) of
        {ok, FmLines} ->
            Props = parse_frontmatter_lines(FmLines),
            build_card(Props);
        {error, _} = Err ->
            Err
    end.

-spec extract_frontmatter([binary()]) ->
    {ok, [binary()]} | {error, no_opening_delimiter}.
extract_frontmatter([<<"---">> | Rest]) ->
    collect_until_closing(Rest, []);
extract_frontmatter([<<"---", _/binary>> | Rest]) ->
    collect_until_closing(Rest, []);
extract_frontmatter(_) ->
    {error, no_opening_delimiter}.

-spec collect_until_closing([binary()], [binary()]) ->
    {ok, [binary()]} | {error, {no_closing_delimiter, non_neg_integer()}}.
collect_until_closing([], Acc) ->
    {error, {no_closing_delimiter, length(Acc)}};
collect_until_closing([<<"---">> | _], Acc) ->
    {ok, lists:reverse(Acc)};
collect_until_closing([<<"---", _/binary>> | _], Acc) ->
    {ok, lists:reverse(Acc)};
collect_until_closing([Line | Rest], Acc) ->
    collect_until_closing(Rest, [Line | Acc]).

-spec parse_frontmatter_lines([binary()]) -> #{binary() => binary() | [binary()]}.
parse_frontmatter_lines(Lines) ->
    parse_fm_lines(Lines, undefined, #{}).

-spec parse_fm_lines([binary()], undefined | binary(), #{binary() => binary() | [binary()]}) ->
    #{binary() => binary() | [binary()]}.
parse_fm_lines([], _CurrentKey, Acc) ->
    Acc;
parse_fm_lines([Line | Rest], CurrentKey, Acc) ->
    Trimmed = string:trim(Line),
    case classify_line(Trimmed) of
        empty ->
            parse_fm_lines(Rest, CurrentKey, Acc);
        section_header ->
            parse_fm_lines(Rest, CurrentKey, Acc);
        {list_item, Value} ->
            case CurrentKey of
                undefined ->
                    parse_fm_lines(Rest, CurrentKey, Acc);
                Key ->
                    Existing = maps:get(Key, Acc, []),
                    NewList =
                        case is_list(Existing) of
                            true -> Existing ++ [Value];
                            false -> [Value]
                        end,
                    parse_fm_lines(Rest, Key, Acc#{Key => NewList})
            end;
        {kv, Key, Value} ->
            parse_fm_lines(Rest, Key, Acc#{Key => Value})
    end.

-spec classify_line(binary()) ->
    empty | section_header | {list_item, binary()} | {kv, binary(), binary() | []}.
classify_line(<<>>) ->
    empty;
classify_line(<<"# ===", _/binary>>) ->
    section_header;
classify_line(<<"- ", ItemRaw/binary>>) ->
    {list_item, unquote(string:trim(ItemRaw))};
classify_line(Line) ->
    case binary:split(Line, <<": ">>) of
        [Key, Value] ->
            parse_kv(string:trim(Key), string:trim(Value));
        [MaybeKV] ->
            case binary:split(MaybeKV, <<":">>) of
                [Key, <<>>] ->
                    {kv, Key, []};
                _ ->
                    empty
            end
    end.

-spec parse_kv(binary(), binary()) -> {kv, binary(), binary() | [binary()]}.
parse_kv(Key, <<"[]">>) ->
    {kv, Key, []};
parse_kv(Key, Value) ->
    {kv, Key, unquote(Value)}.

-spec unquote(binary()) -> binary().
unquote(<<$", Rest/binary>>) ->
    case binary:last(Rest) of
        $" -> binary:part(Rest, 0, byte_size(Rest) - 1);
        _ -> Rest
    end;
unquote(Bin) ->
    Bin.

-spec build_card(#{binary() => binary() | [binary()]}) ->
    {ok, card()} | {error, {missing_field, binary()}}.
build_card(Props) ->
    Required = [
        <<"slug">>,
        <<"concept">>,
        <<"category">>,
        <<"tier">>,
        <<"source">>,
        <<"source_slug">>
    ],
    case check_required(Required, Props) of
        ok ->
            {ok, #{
                slug => get_bin(<<"slug">>, Props),
                concept => get_bin(<<"concept">>, Props),
                category => get_bin(<<"category">>, Props),
                tier => get_bin(<<"tier">>, Props),
                source => get_bin(<<"source">>, Props),
                source_slug => get_bin(<<"source_slug">>, Props),
                prerequisites => get_list(<<"prerequisites">>, Props),
                extends => get_list(<<"extends">>, Props),
                related => get_list(<<"related">>, Props),
                contrasts_with => get_list(<<"contrasts_with">>, Props)
            }};
        {error, _} = Err ->
            Err
    end.

-spec check_required([binary()], map()) -> ok | {error, {missing_field, binary()}}.
check_required([], _Props) ->
    ok;
check_required([Key | Rest], Props) ->
    case maps:is_key(Key, Props) of
        true -> check_required(Rest, Props);
        false -> {error, {missing_field, Key}}
    end.

-spec get_bin(binary(), map()) -> binary().
get_bin(Key, Props) ->
    case maps:get(Key, Props, <<>>) of
        V when is_binary(V) -> V;
        V when is_list(V) -> iolist_to_binary(lists:join(<<", ">>, V));
        _ -> <<>>
    end.

-spec get_list(binary(), map()) -> [binary()].
get_list(Key, Props) ->
    case maps:get(Key, Props, []) of
        V when is_list(V) -> V;
        V when is_binary(V), V =/= <<>> -> [V];
        _ -> []
    end.
