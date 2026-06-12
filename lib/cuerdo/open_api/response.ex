defmodule Cuerdo.OpenAPI.Response do
  @moduledoc """
  OpenAPI [Response Object](https://spec.openapis.org/oas/v3.2.0.html#response-object)
  """
  use Cuerdo.Object,
    schema: %{
      content:
        Zoi.map(Zoi.string(), Zoi.map(%{schema: Zoi.any()}, coerce: true)) |> Zoi.optional()
    }
end
