defmodule Cuerdo.Errors.FailedCriterion do
  defexception [:expression, :criterion, :type]

  @impl true
  def message(%{expression: expression, criterion: criterion, type: type}) do
    "criterion #{criterion} (#{type}) for #{inspect(expression)} failed"
  end
end
