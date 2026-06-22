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
    - `:api_calls` - The list of API calls for the entire workflow in order
  """
  defexception [:path, :error, :api_calls]

  alias Cuerdo.Arazzo.Context.APICalls

  @type t :: %__MODULE__{
          path: [String.t()],
          error: Exception.t(),
          api_calls: nil | [APICalls.t()]
        }

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

  @doc false
  def wrap(error, execution_path, api_calls)

  def wrap(%__MODULE__{} = error, _, api_calls) do
    %__MODULE__{error | api_calls: api_calls}
  end

  def wrap(error, execution_path, api_calls) do
    %__MODULE__{path: execution_path, error: error, api_calls: api_calls}
  end
end
