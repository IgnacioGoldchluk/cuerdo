defmodule Cuerdo.Errors.InvalidFile do
  defexception [:filename, :reason]

  @impl true
  def message(%{filename: filename, reason: reason}) do
    "reading #{filename}: #{inspect(reason)}"
  end
end
