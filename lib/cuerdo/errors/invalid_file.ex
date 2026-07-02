defmodule Cuerdo.Errors.InvalidFile do
  defexception [:filename, :reason]

  use Cuerdo.Errors.Error

  @impl Cuerdo.Errors.Error
  def error_type(_), do: "invalid_file"

  @impl true
  def message(%{filename: filename, reason: reason}) do
    "reading #{filename}: #{inspect(reason)}"
  end
end
