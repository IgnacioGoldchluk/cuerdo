defmodule Cuerdo.Arazzo.Criterion do
  @moduledoc """
  An Arazzo [Criterion Object](https://spec.openapis.org/arazzo/v1.0.1.html#criterion-object)
  """
  alias Cuerdo.Arazzo.Criterion.Simple
  alias Cuerdo.Arazzo.RuntimeExpression
  alias Cuerdo.Errors.{FailedCriterion, InvalidExpression}
  alias Cuerdo.Traversal

  use Cuerdo.Object,
    schema: %{
      context: Zoi.string() |> Zoi.optional(),
      condition: Zoi.string(),
      # Technically `type` can also be a Criterion Expression
      # but let's not support it for now
      type:
        Zoi.string()
        |> Zoi.one_of(["simple", "regex", "jsonpath"])
        |> Zoi.default("simple")
    }

  @type t :: %__MODULE__{context: String.t() | nil, condition: String.t(), type: String.t()}

  @impl Cuerdo.Object
  def validations do
    [:type_and_context]
  end

  def type_and_context(%{type: type, context: context}) do
    case {type == "simple", is_nil(context)} do
      {true, true} -> :ok
      {false, false} -> :ok
      {true, false} -> {:error, "context must be empty for type 'simple'"}
      {false, true} -> {:error, "context is required when type is not 'simple'"}
    end
  end

  @doc """
  Evaluates a list of Criterion until the first failure.
  """
  @spec evaluate_many(list(t()), Traversal.execution_path(), Context.t()) ::
          :ok | {:error, Exception.t()}
  def evaluate_many(criteria, reversed_path, context) when is_list(criteria) do
    Enum.reduce_while(criteria, :ok, fn %__MODULE__{} = criterion, :ok ->
      case evaluate(criterion, reversed_path, context) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Evaluates a single Criterion in for the given path and context. Returns `:ok` on success,
  or `{:error, Exception.t()}` when the criterion evaluatess to false or is invalid
  """
  @spec evaluate(t(), Traversal.execution_path(), Context.t()) :: :ok | {:error, Exception.t()}
  def evaluate(criterion, reversed_path, context)

  def evaluate(%__MODULE__{type: "jsonpath"} = criterion, rev_path, ctx) do
    %{context: criterion_context, condition: query} = criterion

    with {:ok, expression} <- RuntimeExpression.resolve(criterion_context, rev_path, ctx),
         {:ok, query} <- RuntimeExpression.resolve(query, rev_path, ctx),
         {:ok, result} <- JSONPath.values(expression, query) do
      case result do
        [] ->
          {:error, %FailedCriterion{criterion: query, expression: expression, type: "jsonpath"}}

        r when is_list(r) ->
          :ok
      end
    end
  end

  def evaluate(%__MODULE__{type: "regex"} = criterion, rev_path, ctx) do
    %{context: criterion_context, condition: regex} = criterion

    with {:ok, regex} <- RuntimeExpression.resolve(regex, rev_path, ctx),
         {:ok, value} <- RuntimeExpression.resolve(criterion_context, rev_path, ctx),
         val when is_binary(val) or is_number(val) <- Function.identity(value),
         str_val = to_string(val),
         {:ok, pattern} <- Regex.compile(regex),
         {:match?, true} <- {:match?, Regex.match?(pattern, str_val)} do
      :ok
    else
      {:match?, false} ->
        {:error, %FailedCriterion{criterion: regex, expression: criterion_context, type: "regex"}}

      {:error, e} = error when is_exception(e) ->
        error

      _ ->
        {:error, %InvalidExpression{expression: criterion_context}}
    end
  end

  def evaluate(%__MODULE__{type: "simple", context: nil} = criterion, rev_path, ctx) do
    %{condition: condition} = criterion
    # Simple conditions are expanded later, there is no need to expand
    # runtime expressions like in jsonpath and regex cases
    case Simple.evaluate(condition, rev_path, ctx) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, %FailedCriterion{type: "simple", expression: condition}}
      {:error, exc} = error when is_exception(exc) -> error
    end
  end
end
