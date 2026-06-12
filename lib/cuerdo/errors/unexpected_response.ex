defmodule Cuerdo.Errors.UnexpectedResponse do
  defexception [:message]

  @impl true
  def message(%{message: message}) do
    "Unexpected response: #{message}"
  end
end
