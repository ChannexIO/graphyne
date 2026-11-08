defmodule Graphyne.Test do
  @moduledoc """
  Test helpers for code that uses Graphyne. `assert_shape/2` checks a response
  fixture against the fields that the query selects. A fixture with a field
  the query does not select passes the test, but the server never sends that
  field. The helpers take a document or a request body from `Graphyne.payload/2`,
  so a stub can check the exact query that the code sent.
  """

  alias Graphyne.Syntax

  @doc """
  Returns `body` when every key under its `"data"` is a field that the query
  selects. Otherwise raises an `ExUnit.AssertionError` that lists each extra path.
  """
  @spec assert_shape(Graphyne.t() | map(), map()) :: map()
  def assert_shape(query, body) do
    case shape_errors(query, body) do
      [] -> body
      paths -> raise ExUnit.AssertionError, message: "#{name(query)} does not select:\n  " <> Enum.join(paths, "\n  ")
    end
  end

  @doc "Returns the paths under `\"data\"` in `body` that the query does not select."
  @spec shape_errors(Graphyne.t() | map(), map()) :: [String.t()]
  def shape_errors(query, %{} = body) do
    case Syntax.shape(text(query)) do
      {:ok, shape} -> body |> Map.get("data") |> compare(shape, [], []) |> Enum.reverse()
      {:error, _line, message} -> raise ArgumentError, "#{name(query)}: #{message}"
    end
  end

  defp text(%Graphyne{text: text}), do: text
  defp text(%{"query" => text}), do: text

  defp name(%Graphyne{name: name}), do: name
  defp name(%{"operationName" => name}), do: name
  defp name(_payload), do: "the query"

  defp compare(nil, _shape, _path, errors), do: errors

  defp compare(list, shape, path, errors) when is_list(list),
    do: Enum.reduce(list, errors, &compare(&1, shape, path ++ ["[]"], &2))

  defp compare(%{} = map, %{} = shape, path, errors), do: Enum.reduce(map, errors, &compare_field(&1, shape, path, &2))
  defp compare(_value, :leaf, _path, errors), do: errors
  defp compare(_value, %{}, path, errors), do: ["#{format(path)} (a value, the query selects fields of it)" | errors]

  defp compare_field({key, value}, shape, path, errors) when is_map_key(shape, key) do
    compare(value, shape[key], path ++ [key], errors)
  end

  defp compare_field({key, _value}, _shape, path, errors), do: [format(path ++ [key]) | errors]

  defp format(path), do: Enum.reduce(path, "", &append_segment/2)

  defp append_segment("[]", formatted), do: formatted <> "[]"
  defp append_segment(key, ""), do: key
  defp append_segment(key, formatted), do: formatted <> "." <> key
end
