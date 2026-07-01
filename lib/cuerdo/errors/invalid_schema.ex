defmodule Cuerdo.Errors.InvalidSchema do
  defexception [:type, :value]

  @impl true
  def message(%{type: type, value: value}) do
    "Invalid Operation schema (#{type}): #{value}"
  end
end
