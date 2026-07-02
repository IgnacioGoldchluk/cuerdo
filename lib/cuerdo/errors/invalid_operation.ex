defmodule Cuerdo.Errors.InvalidOperation do
  defexception [:value]

  def error_type(_), do: "invalid_operation"

  @impl true
  def message(%{value: value}) do
    "operation name or path is invalid: #{value}"
  end
end
