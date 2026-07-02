defmodule Cuerdo.Errors.InvalidResponse do
  defexception [:response]

  use Cuerdo.Errors.Error

  @impl Cuerdo.Errors.Error
  def error_type(_), do: "invalid_response"

  @impl true
  def message(%{response: response}) do
    "received #{inspect(response)}"
  end
end
