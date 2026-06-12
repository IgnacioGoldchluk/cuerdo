defmodule Cuerdo.Arazzo.Workflow do
  @moduledoc """
  An Arazzo [Workflow](https://spec.openapis.org/arazzo/v1.0.1.html#workflow-object) object
  """
  import Cuerdo.Arazzo.Utils

  alias Cuerdo.Arazzo.{FailureAction, Output, Parameter, Step, SuccessAction}

  use Cuerdo.Object,
    schema: %{
      workflowId: programming_friendly_id(),
      summary: Zoi.string() |> Zoi.optional(),
      description: Zoi.string() |> Zoi.optional(),
      # `inputs` is optional in the spec, but we make it required here
      # because it's the only part we use for parametrizaton
      inputs:
        Zoi.any(
          description: """
          JSON Schema 2020-12 object representing the JSON schema inputs given to the workflow
          """
        ),
      dependsOn: Zoi.array(programming_friendly_id()) |> Zoi.default([]),
      steps: Zoi.array(Step.schema(), min_length: 1),
      failureActions: Zoi.array(FailureAction.schema() |> or_reusable()) |> Zoi.default([]),
      successActions: Zoi.array(SuccessAction.schema() |> or_reusable()) |> Zoi.default([]),
      outputs: Output.schema() |> Zoi.default(%{}),
      parameters:
        Zoi.array(Parameter.schema() |> or_reusable(), unique_items: true) |> Zoi.default([])
    }
end
