defmodule Cuerdo.OpenAPI.Parameter do
  @moduledoc """
  OpenAPI [Parameter Object](https://spec.openapis.org/oas/v3.2.0.html#parameter-object)
  """
  use Cuerdo.Object,
    schema: %{
      name: Zoi.string(),
      in: Zoi.string() |> Zoi.one_of(["query", "querystring", "header", "path"]),
      required: Zoi.boolean() |> Zoi.default(false)
    }

  @type t :: %__MODULE__{}

  @impl Cuerdo.Object
  def validations do
    [:required_in_path]
  end

  def required_in_path(%{in: "path", required: false} = _schema) do
    {:error, "parameter in path must have required = true"}
  end

  def required_in_path(_), do: :ok
end
