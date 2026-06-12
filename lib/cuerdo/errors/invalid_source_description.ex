defmodule Cuerdo.Errors.InvalidSourceDescription do
  defexception [:name, :valid_names]

  @impl true
  def message(%{name: name, valid_names: valid_names}) do
    "Invalid sourceDescription name #{name}. Defined names are: #{Enum.join(valid_names, ", ")}"
  end
end
