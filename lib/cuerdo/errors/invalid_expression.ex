defmodule Cuerdo.Errors.InvalidExpression do
  defexception [:type, :expression, :value]

  @impl true
  def message(%{type: type, expression: expression, value: value}) when is_binary(expression) do
    "invalid #{type} expression: #{expression} - #{value}"
  end

  def message(%{type: type, expression: {path, pointer}, value: value}) do
    "invalid #{type} expression: #{path}/#{pointer} - #{value}"
  end

  def message(%{type: type, expression: expression, value: value}) when is_map(expression) do
    "invalid #{type} expression: #{inspect(expression)} - #{value}"
  end
end
