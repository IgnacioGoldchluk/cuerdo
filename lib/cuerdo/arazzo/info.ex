defmodule Cuerdo.Arazzo.Info do
  @moduledoc """
  An Arazzo [Info Object](https://spec.openapis.org/arazzo/v1.0.1.html#info-object)
  """
  use Cuerdo.Object,
    schema: %{
      title: Zoi.string(),
      version: Zoi.string(),
      summary: Zoi.string() |> Zoi.optional(),
      description: Zoi.string() |> Zoi.optional()
    }
end
