defmodule Cuerdo.OpenAPI.Operation do
  @moduledoc """
  Modified version of OpenAPI [Operation Object](https://spec.openapis.org/oas/v3.2.0.html#operation-object)

  Differences from the standard:
  - Parent `:parameters` are included
  - `:method` is included as a key instead of being implicit in the document's path
  - `:path` is included as a key instead of being a implicit in the document's path
  """

  alias Cuerdo.Arazzo.{Context, Step}
  alias Cuerdo.Errors.InvalidOperation
  alias Cuerdo.OpenAPI

  use Cuerdo.Object,
    schema: %{
      source_description_name: Zoi.string(),
      path: Zoi.string(),
      parameters: Zoi.list(OpenAPI.Parameter.schema()) |> Zoi.optional(),
      requestBody:
        Zoi.map(
          %{
            required: Zoi.boolean() |> Zoi.default(false),
            content: Zoi.map(Zoi.string(), Zoi.map(%{schema: Zoi.any()}, coerce: true))
          },
          coerce: true
        )
        |> Zoi.optional(),
      responses:
        Zoi.map(
          Zoi.union([Zoi.integer(coerce: true), Zoi.literal("default")]),
          OpenAPI.Response.schema()
        ),
      method:
        Zoi.string()
        |> Zoi.one_of([
          "get",
          "put",
          "post",
          "delete",
          "options",
          "head",
          "patch",
          "trace",
          "query"
        ])
    }

  @type t :: %__MODULE__{}

  @doc """
  Returns the operation corresponding to the given step, or an error if the operation
  was not found
  """
  @spec fetch(Step.t(), Context.t()) :: {:ok, t()} | {:error, Exception.t()}
  def fetch(%Step{} = step, %Context{} = ctx) do
    # Easier to delegate both to OpenAPI module for now
    case step do
      %{operationPath: nil, operationId: operation_id} when not is_nil(operation_id) ->
        fetch_by_id(operation_id, ctx)

      %{operationPath: operation_path, operationId: nil} when not is_nil(operation_path) ->
        fetch_by_path(operation_path, ctx)
    end
  end

  defp fetch_by_id(operation_id, %Context{} = ctx) do
    source_description_name = Context.get_source_description_name(operation_id, ctx)

    with {:ok, source_description_value, updated_ctx} <-
           Context.fetch_source_description(ctx, source_description_name),
         [relative_operation_id] <-
           Regex.run(~r/^(?:\$sourceDescriptions\.[\w\-]+\.)?([\w-]+)$/, operation_id,
             capture: :all_but_first
           ),
         {:ok, operation} <-
           OpenAPI.fetch_operation_by_id(
             relative_operation_id,
             source_description_value,
             source_description_name
           ) do
      {:ok, operation, updated_ctx}
    else
      {:error, e} when is_exception(e) -> {:error, e}
      _ -> {:error, %InvalidOperation{value: operation_id}}
    end
  end

  defp fetch_by_path(operation_path, %Context{} = ctx) do
    source_description_name = Context.get_source_description_name(operation_path, ctx)

    with {:ok, source_description_value, updated_ctx} <-
           Context.fetch_source_description(ctx, source_description_name),
         # Beginning is guaranteed to not contain any '#'
         [json_pointer] = Regex.run(~r/^[^#]*(#.*)$/, operation_path, capture: :all_but_first),
         {:ok, operation} <-
           OpenAPI.fetch_operation_by_path(
             json_pointer,
             source_description_value,
             source_description_name
           ) do
      {:ok, operation, updated_ctx}
    else
      {:error, e} when is_exception(e) -> {:error, e}
      _ -> {:error, %InvalidOperation{value: operation_path}}
    end
  end
end
