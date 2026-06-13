defmodule Cuerdo.Errors.FailedCriterion do
  defexception [:expression, :criterion, :type, value: :no_value]

  @impl true
  def message(%{expression: expression, criterion: criterion, type: type, value: :no_value}) do
    "criterion #{criterion} (#{type}) for #{inspect(expression)} failed"
  end

  def message(%{expression: expression, criteron: criterion, type: type, value: value}) do
    "criterion #{criterion} (#{type}) for #{inspect(expression)} failed: #{inspect(value)}"
  end

  # Doesn't have criterion context
  def message(%{type: "simple", expression: expression, value: value}) when is_binary(value) do
    "expression #{expression} (simple) failed. Evaluated to #{value}"
  end
end
