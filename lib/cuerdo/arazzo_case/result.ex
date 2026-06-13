defmodule Cuerdo.ArazzoCase.Result do
  @moduledoc false

  @type status :: :passed | :failed | :error
  defstruct [:workflow_id, :inputs, :execution_time_ms, :reason, :status]

  def format_message(%__MODULE__{status: :error, reason: reason} = result) do
    "ERROR #{result.workflow_id}: #{Exception.message(reason)}"
  end

  def format_message(%__MODULE__{status: :failed} = result) do
    """
    FAILED #{result.workflow_id} in #{result.execution_time_ms}ms
    - reason: #{Exception.message(result.reason)}
    - inputs: #{inspect(result.inputs)}
    """
  end

  def format_message(%__MODULE__{status: :passed} = result) do
    """
    PASSED #{result.workflow_id} in #{result.execution_time_ms}ms
    inputs: #{inspect(result.inputs)}
    """
  end
end
