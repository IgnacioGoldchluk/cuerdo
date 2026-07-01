defmodule Cuerdo.Arazzo.Workflow do
  @moduledoc """
  An Arazzo [Workflow](https://spec.openapis.org/arazzo/v1.0.1.html#workflow-object) object
  """
  import Cuerdo.Arazzo.Utils

  alias Cuerdo.Arazzo
  alias Cuerdo.Arazzo.{Context, FailureAction, Output, Parameter, Step, SuccessAction}

  alias Cuerdo.Errors.{InvalidInputs, InvalidSchema}

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

  @type t :: %__MODULE__{}

  @doc """
  Validates the workflow inputs match the defined inputs schema.
  """
  @spec validate_inputs(any(), t(), Context.t()) :: :ok | {:error, Exception.t()}
  def validate_inputs(
        workflow_inputs,
        %__MODULE__{} = workflow,
        %Context{} = context
      ) do
    with {:ok, inputs_schema} <- Arazzo.build_schema(workflow.inputs, context),
         {:ok, root} <- JSV.build(inputs_schema, resolver: Cuerdo.Resolver),
         {:ok, _} <- JSV.validate(workflow_inputs, root) do
      :ok
    else
      {:error, %JSV.BuildError{} = exc} ->
        {:error, %InvalidSchema{type: :invalid_inputs_schema, value: Exception.message(exc)}}

      {:error, %JSV.ValidationError{} = exc} ->
        {:error, %InvalidInputs{inputs: workflow_inputs, message: Exception.message(exc)}}

      {:error, exc} = error when is_exception(exc) ->
        error
    end
  end
end
