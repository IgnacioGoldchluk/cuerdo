defmodule Cuerdo.Errors.InvalidInputs do
  defexception [:inputs, :message]

  def error_type(_), do: "invalid_inputs"

  @impl true
  def message(%{inputs: inputs, message: message}) do
    "Invalid inputs: #{message}, for #{inspect(inputs, limit: :infinity)}"
  end
end
