defmodule Cuerdo.Errors.InvalidSelector do
  defexception [:context, :selector, :type, :message]

  @type t :: %__MODULE__{
          context: String.t(),
          selector: String.t(),
          type: String.t(),
          message: String.t()
        }

  @impl true
  def message(%{context: context, selector: selector, type: type, message: message}) do
    """
    Invalid selector: #{message}

    type: #{type}
    context: #{context}
    selector: #{selector}
    """
  end
end
