defmodule Graphyne.Syntax do
  @moduledoc """
  Checks a GraphQL executable document at compile time. The grammar lives in
  `src/graphyne_parser.yrl`. On top of it, this module applies
  the rules of https://spec.graphql.org/October2021/#sec-Validation that need
  no schema: one named operation, declared and used variables, constant
  defaults, used fragments. A spread of a fragment from another document is
  not an error: `check/1` returns its name, and `Graphyne.compose/2`
  resolves it. Only the server checks field names and types.
  """

  @lexer :graphyne_lexer
  @parser :graphyne_parser

  @typedoc "The operation name (`nil` for fragments only), its declared variables and the missing fragments."
  @type info :: %{name: String.t() | nil, variables: [String.t()], missing_fragments: [String.t()]}
  @type result :: {:ok, info()} | {:error, pos_integer(), String.t()}

  @typedoc "The response keys that an operation selects. `:leaf` marks a field without a selection set."
  @type shape :: %{String.t() => shape() | :leaf}

  @doc "Parses and checks `text`. The error line counts from the first line of `text`."
  @spec check(String.t()) :: result()
  def check(text) do
    with {:ok, definitions} <- parse(text),
         {operations, fragments} = Enum.split_with(definitions, &operation?/1),
         {:ok, fragments} <- index_fragments(fragments) do
      check_operations(operations, fragments)
    end
  end

  @doc """
  Returns the response shape of the operation in `text`: spread fragments
  and inline fragments merged, aliases as keys. `Graphyne.Test` uses it.
  """
  @spec shape(String.t()) :: {:ok, shape()} | {:error, pos_integer() | nil, String.t()}
  def shape(text) do
    with {:ok, info} <- check(text),
         :ok <- require_complete(info),
         {:ok, definitions} <- parse(text) do
      {[operation], fragments} = Enum.split_with(definitions, &operation?/1)
      {:ok, fragments} = index_fragments(fragments)
      {:ok, selection_shape(elem(operation, 6), fragments, MapSet.new())}
    end
  end

  defp require_complete(%{name: nil}), do: {:error, nil, "the document has no operation"}

  defp require_complete(%{missing_fragments: [_ | _] = missing}) do
    {:error, nil, "the document has no definition of the fragments #{Enum.join(missing, ", ")}"}
  end

  defp require_complete(_info), do: :ok

  defp selection_shape({:selection_set, _line, selections}, fragments, seen) do
    Enum.reduce(selections, %{}, &add_selection(&1, &2, fragments, seen))
  end

  defp add_selection({:field, key, _args, _directives, nil}, shape, _fragments, _seen) do
    merge_shape(shape, %{key => :leaf})
  end

  defp add_selection({:field, key, _args, _directives, selection_set}, shape, fragments, seen) do
    merge_shape(shape, %{key => selection_shape(selection_set, fragments, seen)})
  end

  defp add_selection({:inline_fragment, _directives, selection_set}, shape, fragments, seen) do
    merge_shape(shape, selection_shape(selection_set, fragments, seen))
  end

  # The seen set stops a fragment cycle, which the spec forbids anyway.
  defp add_selection({:spread, _line, name, _directives}, shape, fragments, seen) do
    if MapSet.member?(seen, name) do
      shape
    else
      fragment_set = elem(fragments[name], 5)
      merge_shape(shape, selection_shape(fragment_set, fragments, MapSet.put(seen, name)))
    end
  end

  defp merge_shape(left, right), do: Map.merge(left, right, &merge_field/3)

  defp merge_field(_key, :leaf, :leaf), do: :leaf
  defp merge_field(_key, :leaf, right), do: right
  defp merge_field(_key, left, :leaf), do: left
  defp merge_field(_key, left, right), do: merge_shape(left, right)

  defp parse(text) do
    text
    |> String.to_charlist()
    |> @lexer.string()
    |> parse_tokens()
    |> format_parse_result(text)
  end

  defp parse_tokens({:ok, tokens, _end_line}), do: @parser.parse(tokens)
  defp parse_tokens({:error, error, _end_line}), do: {:error, error}

  defp format_parse_result({:ok, definitions}, _text), do: {:ok, definitions}

  # yecc reports the end of input as line 999999.
  defp format_parse_result({:error, {999_999, module, reason}}, text) do
    format_parse_result({:error, {line_count(text), module, reason}}, text)
  end

  defp format_parse_result({:error, {line, module, reason}}, _text) do
    {:error, line, to_string(module.format_error(reason))}
  end

  defp line_count(text), do: text |> String.split("\n") |> length()

  defp operation?(definition), do: elem(definition, 0) == :operation

  defp index_fragments(fragments) do
    Enum.reduce_while(fragments, {:ok, %{}}, &index_fragment/2)
  end

  defp index_fragment({:fragment, line, name, _type, _directives, _selections} = fragment, {:ok, index}) do
    if Map.has_key?(index, name) do
      {:halt, {:error, line, "the fragment #{name} has more than one definition"}}
    else
      {:cont, {:ok, Map.put(index, name, fragment)}}
    end
  end

  defp check_operations([], _fragments), do: {:ok, %{name: nil, variables: [], missing_fragments: []}}

  defp check_operations([{:operation, line, _type, nil, _vars, _directives, _selections}], _fragments) do
    {:error, line, "the operation has no name"}
  end

  defp check_operations([{:operation, _line, _type, name, vars, directives, selections}], fragments) do
    with {:ok, declared} <- index_variables(vars),
         {used, spread, missing} = follow([directives, selections], fragments),
         :ok <- check_undeclared(used, declared),
         :ok <- check_unused_variables(declared, used, missing),
         :ok <- check_unused_fragments(fragments, spread) do
      {:ok, %{name: name, variables: declared |> Map.keys() |> Enum.sort(), missing_fragments: Enum.sort(missing)}}
    end
  end

  defp check_operations([_first, second | _rest], _fragments) do
    {:error, elem(second, 1), "the document has more than one operation"}
  end

  defp index_variables(vars) do
    Enum.reduce_while(vars, {:ok, %{}}, &index_variable/2)
  end

  defp index_variable({:variable_definition, line, name, default}, {:ok, index}) do
    cond do
      Map.has_key?(index, name) -> {:halt, {:error, line, "the variable $#{name} has more than one definition"}}
      collect(default, []) != [] -> {:halt, {:error, line, "the default of $#{name} uses a variable"}}
      true -> {:cont, {:ok, Map.put(index, name, line)}}
    end
  end

  # Follows each spread into its fragment one time. The spec counts the
  # variables of a spread fragment as variables of the operation.
  defp follow(node, fragments), do: walk(collect(node, []), fragments, {%{}, MapSet.new(), []})

  defp walk([], _fragments, acc), do: acc

  defp walk([{:variable, line, name} | rest], fragments, {used, spread, missing}) do
    walk(rest, fragments, {Map.put_new(used, name, line), spread, missing})
  end

  defp walk([{:spread, _line, name} | rest], fragments, {used, spread, missing} = acc) do
    cond do
      MapSet.member?(spread, name) ->
        walk(rest, fragments, acc)

      Map.has_key?(fragments, name) ->
        walk(collect(fragments[name], rest), fragments, {used, MapSet.put(spread, name), missing})

      true ->
        walk(rest, fragments, {used, MapSet.put(spread, name), [name | missing]})
    end
  end

  # The parse tree keeps names as binaries, so only variables and spreads
  # match here.
  defp collect({:variable, _line, _name} = variable, acc), do: [variable | acc]
  defp collect({:spread, line, name, directives}, acc), do: collect(directives, [{:spread, line, name} | acc])
  defp collect(tuple, acc) when is_tuple(tuple), do: collect(Tuple.to_list(tuple), acc)
  defp collect(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect/2)
  defp collect(_leaf, acc), do: acc

  defp check_undeclared(used, declared) do
    case Enum.find(used, &undeclared?(&1, declared)) do
      nil -> :ok
      {name, line} -> {:error, line, "the variable $#{name} has no declaration"}
    end
  end

  defp undeclared?({name, _line}, declared), do: not Map.has_key?(declared, name)

  # A missing fragment can use any declared variable.
  defp check_unused_variables(_declared, _used, [_missing | _rest]), do: :ok

  defp check_unused_variables(declared, used, []) do
    case Enum.find(declared, &undeclared?(&1, used)) do
      nil -> :ok
      {name, line} -> {:error, line, "the operation does not use the variable $#{name}"}
    end
  end

  defp check_unused_fragments(fragments, spread) do
    case Enum.find(fragments, &unused_fragment?(&1, spread)) do
      nil -> :ok
      {name, fragment} -> {:error, elem(fragment, 1), "the operation does not use the fragment #{name}"}
    end
  end

  defp unused_fragment?({name, _fragment}, spread), do: not MapSet.member?(spread, name)
end
