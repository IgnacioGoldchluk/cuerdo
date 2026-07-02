defmodule Cuerdo.Errors.UnexpectedResponse do
  defexception [:type, :value, :details]

  def error_type(%{type: type}), do: "unexpected_response:#{type}"

  @impl true
  def message(%{type: type, value: value, details: nil}) do
    "Unexpected response (#{type}): #{inspect(value)}"
  end

  def message(%{type: type, value: value, details: details}) do
    "Unexpected response (#{type}): #{inspect(value)}. #{details}"
  end
end
