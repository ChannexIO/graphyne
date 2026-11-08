%% Tokens of a GraphQL executable document, see
%% https://spec.graphql.org/October2021/#sec-Language.Source-Text
%% Graphyne.Syntax calls it at compile time only.

Definitions.

Ignored = [\s\t\r\n,]
Comment = #[^\r\n]*
Name    = [_A-Za-z][_0-9A-Za-z]*
Int     = -?(0|[1-9][0-9]*)
Frac    = \.[0-9]+
Exp     = [eE][+-]?[0-9]+
Punct   = [!$():=@\[\]{}]
Escape  = \\(["\\/bfnrt]|u[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])
String  = "([^"\\\r\n]|{Escape})*"
Block   = """([^"\\]|\\|"[^"]|""[^"]|\\""")*"""

Rules.

{Ignored}+         : skip_token.
{Comment}          : skip_token.
\.\.\.             : {token, {'...', TokenLine}}.
{Punct}            : {token, {list_to_atom(TokenChars), TokenLine}}.
{Int}{Frac}{Exp}?  : {token, {float_value, TokenLine}}.
{Int}{Exp}         : {token, {float_value, TokenLine}}.
{Int}              : {token, {int_value, TokenLine}}.
{Block}            : {token, {string_value, TokenLine}}.
{String}           : {token, {string_value, TokenLine}}.
{Name}             : {token, name(TokenChars, TokenLine)}.

Erlang code.

-define(KEYWORDS, ["query", "mutation", "subscription", "fragment", "on", "true", "false", "null"]).

name(Chars, Line) ->
    case lists:member(Chars, ?KEYWORDS) of
        true -> {list_to_atom(Chars), Line};
        false -> {name, Line, list_to_binary(Chars)}
    end.
