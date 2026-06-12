defmodule Cuerdo.Errors.InvalidOperation do
  defexception [:value]

  @impl true
  def message(%{value: value}) do
    "operation name or path is invalid: #{value}"
  end
end
