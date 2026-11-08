# Graphyne

GraphQL documents as plain text in a `~GQL` sigil. The compile checks the
syntax, so a typo in a query fails `mix compile` with the correct file and
line. It does not wait for the server to send an error.

Graphyne does not make HTTP calls. It builds the request body and reads the
response body. Your app keeps its own HTTP client, auth and retries.

## Install

```elixir
{:graphyne, github: "ChannexIO/graphyne", tag: "v0.1.0"}
```

Elixir `~> 1.18`. No runtime dependencies. The lexer and the grammar are
leex and yecc files that Mix compiles.

## Use

```elixir
defmodule MyApp.Issues do
  use Graphyne

  @list ~GQL"""
  query ListIssues($owner: String!, $name: String!, $after: String) {
    repository(owner: $owner, name: $name) {
      issues(first: 20, after: $after, states: OPEN) {
        pageInfo { endCursor hasNextPage }
        nodes { number title }
      }
    }
  }
  """

  def list(owner, name, cursor \\ nil) do
    @list
    |> Graphyne.payload(%{"owner" => owner, "name" => name, "after" => cursor})
    |> MyApp.HTTP.post_json("/graphql")
    |> handle_response()
  end

  defp handle_response({:ok, body}), do: Graphyne.result(body)
  defp handle_response(error), do: error
end
```

`Graphyne.payload/2` returns `%{"query" => text, "operationName" => name, "variables" => map}`.
The request and the response are JSON, so both use string keys, with the
names exactly as in the GraphQL text. That includes the fields of an input
object, for example `%{"filter" => %{"reviewId" => id}}`.

`payload/2` raises an `ArgumentError` for a key that the document does not
declare, so a typo such as `"ownr"` fails in your tests and not on the
server. It leaves out each variable with a `nil` value, so the argument
counts as not given.

`Graphyne.result/1` takes the decoded body and returns one of these:

| Body | Result |
|---|---|
| `data`, no `errors` | `{:ok, data}` |
| a non-empty `errors` list | `{:error, %Graphyne.Error{errors: errors, data: data_or_nil}}` |
| anything else | `{:error, body}` |

A partial result is an error that keeps its `data`. Use the helpers to
match error codes:

```elixir
case Graphyne.result(body) do
  {:ok, data} ->
    {:ok, data}

  {:error, %Graphyne.Error{} = error} ->
    if Graphyne.Error.code?(error, "FORBIDDEN"), do: {:error, :forbidden}, else: {:error, error}

  {:error, body} ->
    {:error, body}
end
```

## Fragments

A query can spread a fragment from another document. The sigil records the
missing fragment, and `compose/2` adds it. `payload/2` raises an
`ArgumentError` if a fragment is still missing.

```elixir
@issue_fields ~GQL"""
fragment IssueFields on Issue { number title state }
"""

@find_query ~GQL"""
query FindIssue($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) { ...IssueFields }
  }
}
"""

@find compose(@find_query, [@issue_fields])
```

## Testing

A response fixture can drift from the query. A fixture with a field that the
query does not select still passes the test, but the server never sends that
field. `Graphyne.Test.assert_shape/2` catches this. It returns the body, so it
fits inside a stub. It also takes the request body that `payload/2` builds,
so the stub checks the exact query that your code sent:

```elixir
import Graphyne.Test

stub(MyApp.HTTPMock, :post_json, fn %{"operationName" => "ListIssues"} = payload, _path ->
  {:ok, assert_shape(payload, load_fixture("list_issues.json"))}
end)
```

A failure lists each extra path:

```
ListIssues does not select:
  repository.issues.nodes[].body
```

`Graphyne.Test.shape_errors/2` returns the same paths as a list and does not raise.

## What the compile checks

The grammar follows the executable part of the
[October 2021 spec](https://spec.graphql.org/October2021/#sec-Document).
On top of it, `Graphyne.Syntax` applies the
[validation rules](https://spec.graphql.org/October2021/#sec-Validation)
that need no schema:

- The document has exactly one operation, and the operation has a name.
- Each variable has one declaration, and the operation uses each declared variable.
- A default value does not use a variable.
- Each fragment has one definition, and the operation uses each fragment.

Field names, argument names and types need the server schema. The server
checks them.

## Release

A release is a feature commit, then a version commit that changes
`@version` in `mix.exs`, then an annotated tag `vX.Y.Z` on the version commit.

## License

MIT, see `LICENSE`.
