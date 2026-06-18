defmodule Cuerdo.CLI.Errors.UnexpectedArgs do
  defexception [:args]

  @impl true
  def message(%{args: args}) do
    "Unexpected arguments: #{Enum.map_join(args, ", ", &arg/1)}"
  end

  defp arg({flag, nil}), do: flag
  defp arg({flag, value}), do: "#{flag}=#{value}"
end
