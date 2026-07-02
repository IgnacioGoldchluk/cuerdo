defmodule Cuerdo.Errors.InvalidResponse do
  defexception [:response]

  def error_type(_), do: "invalid_response"

  @impl true
  def message(%{response: response}) do
    "received #{inspect(response)}"
  end
end
