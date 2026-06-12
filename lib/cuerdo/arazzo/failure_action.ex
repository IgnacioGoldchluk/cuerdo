defmodule Cuerdo.Arazzo.FailureAction do
  @moduledoc """
  An Arazzo [Failure Action](https://spec.openapis.org/arazzo/v1.0.1.html#failure-action-object) object
  """
  import Cuerdo.Arazzo.Utils

  alias Cuerdo.Arazzo.Criterion

  use Cuerdo.Object,
    schema: %{
      name: Zoi.string(),
      type: Zoi.string() |> Zoi.one_of(["retry", "end", "goto"]),
      workflowId: programming_friendly_id() |> Zoi.optional(),
      stepId: programming_friendly_id() |> Zoi.optional(),
      criteria: Zoi.array(Criterion.schema(), min_length: 1),
      retryLimit:
        Zoi.integer(
          description:
            "Number of additional attempts to make before failing the step. Defaults to 1"
        )
        |> Zoi.gt(0)
        |> Zoi.default(1),
      retryAfter:
        Zoi.integer(description: "Seconds to delay after another attempt is made")
        |> Zoi.gt(0)
        |> Zoi.optional()
    }

  @impl Cuerdo.Object
  def validations do
    [:mutually_exclusive_ids, :retry_after]
  end

  def retry_after(%{type: "retry", retryAfter: nil}) do
    {:error, "'retryAfter' is required when 'type' is 'retry'"}
  end

  def retry_after(_), do: :ok

  def mutually_exclusive_ids(%{type: "end"}), do: :ok

  def mutually_exclusive_ids(%{workflowId: workflow_id, stepId: step_id} = failure_action) do
    case {is_nil(workflow_id), is_nil(step_id)} do
      {true, false} ->
        :ok

      {false, true} ->
        :ok

      {true, true} ->
        {:error, "type '#{failure_action.type}' given with no 'workflowId' or 'stepId'"}

      {false, false} ->
        {
          :error,
          "type '#{failure_action.type}' given with both 'workflowId' (#{workflow_id}) and 'stepId' (#{step_id}). Only one must be set"
        }
    end
  end
end
