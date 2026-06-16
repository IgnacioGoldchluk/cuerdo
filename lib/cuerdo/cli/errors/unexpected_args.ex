defmodule Cuerdo.CLI.Errors.UnexpectedArgs do
  defexception [:args]

  @impl true
  def message(%{args: args}) do
    "Unexpected arguments: #{Enum.join(args, ", ")}"
  end
end
