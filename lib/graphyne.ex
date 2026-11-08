defmodule Graphyne do
  @moduledoc """
  GraphQL documents as plain text, checked at compile time. The `~GQL` sigil
  parses the text (`Graphyne.Syntax`) and keeps the operation name.
  `compose/2` adds fragments from other documents. `payload/2` builds the
  request body, and `result/1` reads the response body. Both use string keys,
  as JSON does. The HTTP call stays with the caller.
  `use Graphyne` imports `sigil_GQL/2` and `compose/2`.
  """

  alias Graphyne.Error
  alias Graphyne.Syntax

  @enforce_keys [:name, :text]
  defstruct [:name, :text, variables: [], missing_fragments: []]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          text: String.t(),
          variables: [String.t()],
          missing_fragments: [String.t()]
        }

  defmacro __using__(_opts) do
    quote do
      import Graphyne, only: [sigil_GQL: 2, compose: 2]
    end
  end

  @doc "Builds a document from GraphQL text. A syntax error fails the compile."
  defmacro sigil_GQL({:<<>>, meta, [text]}, []) when is_binary(text) do
    # The text of a heredoc starts on the line after the sigil.
    first_line = __CALLER__.line + if(Keyword.has_key?(meta, :indentation), do: 1, else: 0)

    case new(text) do
      {:ok, document} ->
        Macro.escape(document)

      {:error, line, message} ->
        raise CompileError, file: __CALLER__.file, line: first_line + line - 1, description: "~GQL: " <> message
    end
  end

  @doc "Appends fragment documents to a document. The result must have all its fragments."
  @spec compose(t(), [t()]) :: t()
  def compose(%__MODULE__{} = document, fragments) do
    text = Enum.map_join([document | fragments], "\n", & &1.text)

    case new(text) do
      {:ok, %{missing_fragments: []} = document} -> document
      {:ok, document} -> raise ArgumentError, missing_fragments_message(document)
      {:error, line, message} -> raise ArgumentError, "line #{line} of the composed document: #{message}"
    end
  end

  defp new(text) do
    with {:ok, info} <- Syntax.check(text) do
      {:ok, struct!(__MODULE__, Map.put(info, :text, text))}
    end
  end

  @doc """
  Builds the request body of https://graphql.github.io/graphql-over-http/draft/#sec-Request-Parameters.
  Variable keys are the names that the document declares, as strings. A key
  the document does not declare raises. Variables with a `nil` value are left
  out, so that the argument counts as not given.
  """
  @spec payload(t(), %{String.t() => term()}) :: %{String.t() => term()}
  def payload(%__MODULE__{missing_fragments: [_ | _]} = document, _variables) do
    raise ArgumentError, missing_fragments_message(document)
  end

  def payload(%__MODULE__{name: name, text: text} = document, variables) when is_binary(name) do
    unknown =
      variables
      |> Map.keys()
      |> Enum.reject(&declared?(document, &1))

    if unknown != [], do: raise(ArgumentError, unknown_variables_message(document, unknown))

    %{"query" => text, "operationName" => name, "variables" => Map.reject(variables, &nil_value?/1)}
  end

  defp declared?(document, key), do: key in document.variables
  defp nil_value?({_name, value}), do: is_nil(value)

  defp unknown_variables_message(document, unknown) do
    declared = Enum.map_join(document.variables, ", ", &inspect/1)
    unknown = Enum.map_join(Enum.sort(unknown), ", ", &inspect/1)
    "#{document.name} declares no variables #{unknown}, it declares: #{declared}"
  end

  defp missing_fragments_message(document) do
    fragments = Enum.join(document.missing_fragments, ", ")
    "#{document.name} has no definition of the fragments #{fragments}, add them with compose/2"
  end

  @doc """
  Reads a decoded response body. A non-empty `errors` list gives a
  `Graphyne.Error` that keeps the partial `data`. A body that is not a
  GraphQL response comes back as `{:error, body}`.
  """
  @spec result(term()) :: {:ok, map() | nil} | {:error, Error.t()} | {:error, term()}
  def result(%{"errors" => [_ | _] = errors} = body), do: {:error, %Error{errors: errors, data: body["data"]}}
  def result(%{"data" => data}), do: {:ok, data}
  def result(body), do: {:error, body}
end
