defmodule Cuerdo.Errors.InvalidSchema do
  defexception [:type, :value]

  def error_type(%{type: type}), do: "invalid_schema:#{type}"

  @impl true
  def message(%{type: type, value: value}) do
    "Invalid Operation schema (#{type}): #{value}"
  end
end
