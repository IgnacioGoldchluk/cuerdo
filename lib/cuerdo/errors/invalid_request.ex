defmodule Cuerdo.Errors.InvalidRequest do
  defexception [:message]

  @impl true
  def message(%{message: message}) do
    "Invalid request: #{message}"
  end
end
