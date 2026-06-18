defmodule Cuerdo.Arazzo.Selector do
  @moduledoc """
  An Arazzo [Selector](https://spec.openapis.org/arazzo/v1.1.0#selector-object) object
  """
  alias Cuerdo.Errors.InvalidSelector

  use Cuerdo.Object,
    schema: %{
      context: Zoi.string(),
      selector: Zoi.string(),
      type: Zoi.string() |> Zoi.one_of(["jsonpath", "jsonpointer"])
    }

  @type t :: %__MODULE__{}

  @doc """
  Resolves a selector
  """
  @spec resolve(String.t(), String.t(), String.t()) ::
          {:ok, any()} | {:error, InvalidSelector.t()}
  def resolve(value, type, selector) do
    {:ok, do_resolve(value, type, selector)}
  rescue
    # TODO: Fix this
    _ -> {:error, %InvalidSelector{context: value, type: type, selector: selector}}
  end

  defp do_resolve(value, "jsonpointer", selector) do
    RockSolid.Traversal.fetch_in_schema!(value, RockSolid.Traversal.to_path(selector))
  end

  defp do_resolve(value, "jsonpath", selector) do
    # Assuming that selector always expects a single value, since JSONPath
    # always returns a list as descrbed in RFC-9535
    {:ok, [resolved]} = JSONPath.values(value, selector)
    resolved
  end
end
