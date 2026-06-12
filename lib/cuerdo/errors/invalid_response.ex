defmodule Cuerdo.Errors.InvalidResponse do
  defexception [:response]

  @impl true
  def message(%{response: response}) do
    "received #{inspect(response)}"
  end
end
