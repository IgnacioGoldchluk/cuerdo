defmodule Cuerdo.Arazzo.Components do
  @moduledoc """
  An Arazzo [Components Object](https://spec.openapis.org/arazzo/v1.0.1.html#components-object)
  """
  import Cuerdo.Arazzo.Utils

  alias Cuerdo.Arazzo.{FailureAction, Parameter, SuccessAction}

  use Cuerdo.Object,
    schema: %{
      inputs: Zoi.map(programming_friendly_id(), Zoi.any()) |> Zoi.default(%{}),
      parameters: Zoi.map(programming_friendly_id(), Parameter.schema()) |> Zoi.default(%{}),
      successActions:
        Zoi.map(programming_friendly_id(), SuccessAction.schema()) |> Zoi.default(%{}),
      failureActions:
        Zoi.map(programming_friendly_id(), FailureAction.schema()) |> Zoi.default(%{})
    }
end
