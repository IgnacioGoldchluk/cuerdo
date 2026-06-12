defmodule Cuerdo.Arazzo.SourceDescription do
  @moduledoc """
  An Arazzo [Source Description](https://spec.openapis.org/arazzo/v1.0.1.html#source-description-object) object
  """
  import Cuerdo.Arazzo.Utils

  use Cuerdo.Object,
    schema: %{
      name: programming_friendly_id(),
      url: Zoi.string(),
      type: Zoi.string() |> Zoi.one_of(["openapi", "arazzo"]),
      # To be resolved later
      value: Zoi.any() |> Zoi.default(nil)
    }
end
