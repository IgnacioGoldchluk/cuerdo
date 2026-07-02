defmodule Cuerdo.Errors.MissingParameters do
  defexception [:parameters]

  @type t :: %__MODULE__{parameters: [{String.t(), String.t()}]}

  def error_type(_), do: "missing_parameters"

  @impl true
  def message(%{parameters: parameters}) do
    "Missing required parameters: #{Enum.map_join(parameters, ",", &format_param/1)}"
  end

  defp format_param({name, in_}), do: "#{name} (#{in_})"
end
