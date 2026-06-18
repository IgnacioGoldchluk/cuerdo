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
  def resolve(value, type, selector)

  def resolve(value, "jsonpointer" = type, selector) do
    case RockSolid.Traversal.fetch_in_schema(value, RockSolid.Traversal.to_path(selector)) do
      {:ok, value} ->
        {:ok, value}

      {:error, exc} ->
        {:error,
         %InvalidSelector{
           context: value,
           type: type,
           selector: selector,
           message: Exception.message(exc)
         }}
    end
  end

  def resolve(value, "jsonpath" = type, selector) do
    case JSONPath.values(value, selector) do
      {:ok, [value]} ->
        {:ok, value}

      {:ok, unexpected} ->
        {:error,
         %InvalidSelector{
           context: value,
           type: type,
           selector: selector,
           message: "expected single value, got: #{inspect(unexpected)}"
         }}

      {:error, exc} ->
        {:error,
         %InvalidSelector{
           context: value,
           type: type,
           selector: selector,
           message: Exception.message(exc)
         }}
    end
  end
end
