defmodule Cuerdo.Errors.InvalidSelector do
  defexception [:context, :selector, :type]

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
