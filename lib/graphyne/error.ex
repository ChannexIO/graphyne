defmodule Graphyne.Error do
  @moduledoc """
  The `errors` list of a GraphQL response, see
  https://spec.graphql.org/October2021/#sec-Errors. `data` holds the partial
  result, or `nil` when the response has none.
  """

  defexception [:errors, :data]

  @type t :: %__MODULE__{errors: [map()], data: map() | nil}

  @impl true
  def message(%__MODULE__{errors: errors}), do: Enum.map_join(errors, "; ", &error_message/1)

  @doc "Tells if an error has one of the given `extensions.code` values."
  @spec code?(t(), String.t() | [String.t()]) :: boolean()
  def code?(%__MODULE__{errors: errors}, codes) do
    Enum.any?(errors, &has_code?(&1, List.wrap(codes)))
  end

  @doc "Tells if an error has the given message."
  @spec message?(t(), String.t()) :: boolean()
  def message?(%__MODULE__{errors: errors}, message) do
    Enum.any?(errors, &has_message?(&1, message))
  end

  defp has_code?(error, codes), do: get_in(error, ["extensions", "code"]) in codes
  defp has_message?(error, message), do: error_message(error) == message
  defp error_message(error), do: error["message"]
end
