defmodule Cuerdo.Arazzo.Parameter do
  @moduledoc """
  An Arazzo [Parameter Object](https://spec.openapis.org/arazzo/v1.0.1.html#parameter-object)
  """

  alias Cuerdo.Arazzo.{Context, ReusableObject, RuntimeExpression, Selector}
  alias Cuerdo.Errors.MissingParameters
  alias Cuerdo.OpenAPI
  alias Cuerdo.Traversal

  @type t :: %__MODULE__{}

  # If the parent step specifies `workflowId` then all parameters
  # map to workflow input. All other cases (using `operationId`) require
  # `in` to be specified.
  # Since we are not using composable workflows for now we'll keep it as required
  use Cuerdo.Object,
    schema: %{
      name: Zoi.string(),
      in: Zoi.string() |> Zoi.one_of(["path", "query", "header", "cookie"]) |> Zoi.optional(),
      value: Zoi.union([Selector.schema(), Zoi.any()])
    }

  @doc """
  Receives a list of parameters and reusable objects and resolves them to a list of parameters
  """
  @spec resolve(list(t()), Traversal.execution_path(), Context.t()) ::
          {:ok, [t()]} | {:error, Exception.t()}
  def resolve(parameters, reversed_path, context) when is_list(parameters) do
    case resolve_reusable_objects(parameters, context) do
      {:ok, parameters} ->
        parameters
        |> Enum.uniq_by(fn %__MODULE__{in: in_, name: name} -> {in_, name} end)
        |> resolve_parameters_runtime_expressions(reversed_path, context)

      {:error, e} = error when is_exception(e) ->
        error
    end
  end

  defp resolve_reusable_objects(parameters, %Context{} = context) do
    Enum.reduce_while(parameters, [], fn
      %__MODULE__{} = parameter, params ->
        {:cont, [parameter | params]}

      %ReusableObject{} = reusable_object, params ->
        case ReusableObject.resolve(reusable_object, context) do
          {:ok, parameter} -> {:cont, [parameter | params]}
          {:error, exc} -> {:halt, exc}
        end
    end)
    |> case do
      parameters when is_list(parameters) -> {:ok, Enum.reverse(parameters)}
      exc when is_exception(exc) -> {:error, exc}
    end
  end

  defp resolve_parameters_runtime_expressions(parameters, rev_path, %Context{} = context) do
    Enum.reduce_while(parameters, [], fn %__MODULE__{value: value} = parameter, params ->
      case RuntimeExpression.resolve(value, rev_path, context) do
        {:ok, replaced} -> {:cont, [%__MODULE__{parameter | value: replaced} | params]}
        {:error, exc} -> {:halt, exc}
      end
    end)
    |> case do
      params when is_list(params) -> {:ok, Enum.reverse(params)}
      exc when is_exception(exc) -> {:error, exc}
    end
  end

  @doc """
  Validates whether all required `operation_parameters` are present in `parameters`.
  """
  @spec all_present(list(t()), list(OpenAPI.Parameter.t())) ::
          :ok | {:error, MissingParameters.t()}
  def all_present(parameters, operation_parameters)
      when is_list(parameters) and is_list(operation_parameters) do
    parameters = MapSet.new(parameters, &parameter_id/1)

    operation_parameters
    |> Enum.filter(&(&1.required == true))
    |> Enum.map(&parameter_id/1)
    |> Enum.reject(&(&1 in parameters))
    |> case do
      [] -> :ok
      missing -> {:error, %MissingParameters{parameters: missing}}
    end
  end

  defp parameter_id(%{in: in_, name: name}), do: {name, in_}
end
