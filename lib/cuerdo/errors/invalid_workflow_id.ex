defmodule Cuerdo.Errors.InvalidWorkflowId do
  defexception [:id, :valid_ids]

  @type t :: %__MODULE__{id: String.t(), valid_ids: [String.t()]}

  def error_type(_), do: "invalid_workflow_id"

  @impl true
  def message(%{id: id, valid_ids: valid_ids}) do
    "Invalid workflowId #{id}. Defined workflow ids are: #{Enum.join(valid_ids, ", ")}"
  end
end
