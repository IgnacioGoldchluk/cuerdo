defmodule Cuerdo.Errors.InvalidExpression do
  defexception [:expression, :stacktrace]

  @impl true
  def message(%{expression: expression}) when is_binary(expression) do
    "invalid expression: #{expression}"
  end

  def message(%{expression: {path, pointer}}) do
    "invalid expression: #{path}/#{pointer}"
  end

  def message(%{expression: expression}) when is_map(expression) do
    "invalid expression: #{inspect(expression)}"
  end
end
