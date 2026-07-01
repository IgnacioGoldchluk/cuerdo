defmodule Cuerdo.Arazzo.ReusableObject do
  @moduledoc """
  An Arazzo [Reusable Object](https://spec.openapis.org/arazzo/v1.0.1.html#reusable-object)
  """
  alias Cuerdo.Arazzo.{Context, Parameter}

  alias Cuerdo.Errors.InvalidExpression

  use Cuerdo.Object,
    schema: %{reference: Zoi.string(), value: Zoi.string() |> Zoi.optional()}

  @type t :: %__MODULE__{}
  @doc """
  Resolves a Reusable Object expression
  """
  @spec resolve(t(), Context.t()) :: {:ok, Parameter.t()} | {:error, Exception.t()}
  def resolve(
        %__MODULE__{reference: "$components.parameters." <> name = ref} = obj,
        %Context{} = ctx
      ) do
    case ctx.document do
      %{components: %{parameters: params}} when is_map_key(params, name) ->
        parameter = Map.fetch!(params, name)

        if(is_nil(obj.value),
          do: {:ok, parameter},
          else: {:ok, Map.put(parameter, :value, obj.value)}
        )

      _ ->
        {:error, %InvalidExpression{type: :parameter, expression: ref, value: "not in document"}}
    end
  end
end
