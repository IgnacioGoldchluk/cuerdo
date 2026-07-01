defmodule Cuerdo.Errors.InvalidRequest do
  defexception [:type, :value]

  @impl true
  def message(%{type: :missing_body}) do
    "Request body required but not present"
  end

  @impl true
  def message(%{type: type, value: value}) do
    "Invalid Request (#{type}): #{inspect(value)}"
  end
end
