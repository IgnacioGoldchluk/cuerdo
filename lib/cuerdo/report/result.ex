defmodule Cuerdo.Report.Result do
  @moduledoc false

  @type status :: :passed | :failed | :error
  defstruct [:workflow_id, :inputs, :error, :status, :http_calls]

  def format_message(%__MODULE__{status: :error, error: reason} = result) do
    "ERROR #{result.workflow_id}: #{Exception.message(reason)}"
  end

  def format_message(%__MODULE__{status: :failed} = result) do
    """
    FAILED #{result.workflow_id} in #{execution_time_ms(result)}ms
    - reason: #{Exception.message(result.error)}
    - inputs: #{inspect(result.inputs)}
    """
  end

  def execution_time_ms(%__MODULE__{http_calls: http_calls}) do
    Enum.sum_by(http_calls, & &1.time_ms)
  end
end
