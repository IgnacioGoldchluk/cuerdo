defmodule Cuerdo.Arazzo.SuccessAction do
  @moduledoc """
  An Arazzo [Success Action](https://spec.openapis.org/arazzo/v1.0.1.html#success-action-object) object
  """
  alias Cuerdo.Arazzo.Criterion
  import Cuerdo.Arazzo.Utils

  use Cuerdo.Object,
    schema: %{
      name: Zoi.string(),
      type: Zoi.string() |> Zoi.one_of(["end", "goto"]),
      workflowId: programming_friendly_id() |> Zoi.optional(),
      stepId: programming_friendly_id() |> Zoi.optional(),
      criteria: Zoi.array(Criterion.schema(), min_length: 1)
    }

  @impl Cuerdo.Object
  def validations do
    [:mutually_exclusive_ids]
  end

  def mutually_exclusive_ids(%{type: "end"}), do: :ok

  def mutually_exclusive_ids(%{type: "goto"} = success_action) do
    %{workflowId: workflow_id, stepId: step_id} = success_action

    case {is_nil(workflow_id), is_nil(step_id)} do
      {true, false} ->
        :ok

      {false, true} ->
        :ok

      {true, true} ->
        {:error, "type 'goto' given with no 'workflowId' or 'stepId'"}

      {false, false} ->
        {
          :error,
          "type 'goto' given with both 'workflowId' (#{workflow_id}) and 'stepId' (#{step_id}). Only one must be set"
        }
    end
  end
end
