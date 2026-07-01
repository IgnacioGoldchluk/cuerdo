defmodule Cuerdo.Errors.FailedCondition do
  defexception [:type, :expression, :value]

  @impl true
  def message(%{type: type, expression: expr, values: value}) do
    "Condition failed (#{type}): #{expr} (#{value})"
  end
end
