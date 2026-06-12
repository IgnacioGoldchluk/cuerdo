defmodule Cuerdo.Errors.MissingParameters do
  defexception [:parameters]

  @impl true
  def message(%{parameters: parameters}) do
    "Missing required parameters: #{Enum.map_join(parameters, ",", &format_param/1)}"
  end

  defp format_param({name, in_}), do: "#{name} (#{in_})"
end
