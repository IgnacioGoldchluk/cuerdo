defmodule Cuerdo.Errors.InvalidOperation do
  defexception [:value]

  use Cuerdo.Errors.Error

  @impl Cuerdo.Errors.Error
  def error_type(_), do: "invalid_operation"

  @impl true
  def message(%{value: value}) do
    "operation name or path is invalid: #{value}"
  end
end
