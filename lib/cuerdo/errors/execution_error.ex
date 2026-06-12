defmodule Cuerdo.Errors.ExecutionError do
  @moduledoc """
  Error structure that wraps any raised or returned error during the
  execution of an Arazzo workflow/step

  ## Fields
    - `:error` - The original error/exception
    - `:path` - The execution path. For self-contained steps within the workflow
    it has the form `[workflowId, stepId]`. If the step references another workflow
    and a step fails within the referenced workflow then it is of the form
    `[mainWorkflowId, mainStepId, referencedWorkflowId, failedStepId]` and so on
  """
  defexception [:path, :error]

  @type t :: %__MODULE__{path: [String.t()], error: Exception.t()}

  @impl true
  def message(%{path: path, error: error}) do
    "executing #{Enum.join(path, ".")}: #{Exception.message(error)}"
  end

  @doc false
  # Wraps the error in an `ExecutionError` exception
  def wrap(error, execution_path)

  def wrap(%__MODULE__{} = error, _execution_path), do: error

  def wrap(error, execution_path) when is_exception(error) do
    %__MODULE__{path: execution_path, error: error}
  end
end
