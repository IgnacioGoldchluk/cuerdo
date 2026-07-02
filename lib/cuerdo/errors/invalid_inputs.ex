defmodule Cuerdo.Errors.InvalidInputs do
  defexception [:inputs, :message]

  use Cuerdo.Errors.Error

  @impl Cuerdo.Errors.Error
  def error_type(_), do: "invalid_inputs"

  @impl true
  def message(%{inputs: inputs, message: message}) do
    "Invalid inputs: #{message}, for #{inspect(inputs, limit: :infinity)}"
  end
end
