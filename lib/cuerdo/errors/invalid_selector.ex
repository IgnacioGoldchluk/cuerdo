defmodule Cuerdo.Errors.InvalidSelector do
  defexception [:context, :selector, :type, :message]

  @type t :: %__MODULE__{
          context: String.t(),
          selector: String.t(),
          type: String.t(),
          message: String.t()
        }

  use Cuerdo.Errors.Error

  @impl Cuerdo.Errors.Error
  def error_type(%{type: type}), do: "invalid_selector:#{type}"

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
