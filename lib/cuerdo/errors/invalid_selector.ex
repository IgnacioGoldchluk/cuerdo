defmodule Cuerdo.Errors.InvalidSelector do
  defexception [:context, :selector, :type]

  @type t :: %__MODULE__{context: String.t(), selector: String.t(), type: String.t()}

  @impl true
  def message(%{context: context, selector: selector, type: type}) do
    """
    Invalid selector

    type: #{type}
    context: #{context}
    selector: #{selector}
    """
  end
end
