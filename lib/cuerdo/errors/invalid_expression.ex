defmodule Cuerdo.Errors.InvalidExpression do
  defexception [:expression, :message]

  @impl true
  def message(%{expression: expression, message: message}) when is_binary(expression) do
    "invalid expression: #{expression} - #{message}"
  end

  def message(%{expression: {path, pointer}, message: message}) do
    "invalid expression: #{path}/#{pointer} - #{message}"
  end

  def message(%{expression: expression, message: message}) when is_map(expression) do
    "invalid expression: #{inspect(expression)} - #{message}"
  end
end
