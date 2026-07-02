defmodule Cuerdo.Errors.Error do
  @moduledoc """
  Base Error behaviour
  """
  @callback error_type(Exception.t()) :: String.t()

  defmacro __using__(_opts) do
    caller = __CALLER__.module

    quote bind_quoted: [caller: caller] do
      @behaviour Cuerdo.Errors.Error

      defimpl JSON.Encoder, for: caller do
        def encode(error, _encoder) do
          %{
            "type" => error.__struct__.error_type(error),
            "value" => Exception.message(error)
          }
          |> JSON.encode!()
        end
      end
    end
  end
end
