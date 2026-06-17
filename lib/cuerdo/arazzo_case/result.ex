defmodule Cuerdo.ArazzoCase.Result do
  @moduledoc false

  @type status :: :passed | :failed | :error
  defstruct [:workflow_id, :inputs, :reason, :status, execution_time_ms: 0]

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

  defimpl JSON.Encoder, for: Cuerdo.ArazzoCase.Result do
    def encode(%Cuerdo.ArazzoCase.Result{} = result, encoder) do
      result
      |> Map.from_struct()
      |> Map.update!(:reason, fn
        nil -> nil
        exc when is_exception(exc) -> Exception.message(exc)
      end)
      |> JSON.Encoder.encode(encoder)
    end
  end
end
