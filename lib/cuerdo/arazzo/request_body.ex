defmodule Cuerdo.Arazzo.RequestBody do
  @moduledoc """
  An Arazzo [Request Body Object](https://spec.openapis.org/arazzo/v1.0.1.html#request-body-object)
  """
  alias Cuerdo.Arazzo.{Context, HTTP, Replacement, RuntimeExpression}
  alias Cuerdo.Errors.InvalidRequest
  alias Cuerdo.OpenAPI

  alias Cuerdo.Traversal

  use Cuerdo.Object,
    schema: %{
      # If contentType is missing then we should use the one from the operationId/operationPah
      contentType:
        Zoi.string()
        |> Zoi.one_of([
          "application/json",
          "application/ld+json",
          "application/vnd.api+json",
          "application/x-www-form-urlencoded"
        ]),
      payload: Zoi.any(),
      replacements: Zoi.array(Replacement.schema()) |> Zoi.default([])
    }

  @type t :: %__MODULE__{}
  @type request_body :: %{body: any(), content_type: String.t() | nil}

  def json?(content_type) do
    content_type in ["application/json", "application/ld+json", "application/vnd.api+json"]
  end

  @doc """
  Resolves and fully expands the request body
  """
  @spec resolve(t() | nil, Traversal.execution_path(), Context.t()) ::
          {:ok, nil | request_body()} | {:error, Exception.t()}
  def resolve(body, reversed_path, context)
  def resolve(nil, _, _), do: {:ok, nil}

  def resolve(%__MODULE__{} = request_body, rev_path, %Context{} = ctx) do
    %{payload: payload, replacements: replacements} = request_body

    with {:ok, expanded_body} <- RuntimeExpression.resolve(payload, rev_path, ctx),
         {:ok, body} <- Replacement.apply_many(replacements, expanded_body, rev_path, ctx) do
      body =
        if (is_list(body) or is_map(body)) and json?(request_body.contentType) do
          JSON.encode!(body)
        else
          body
        end

      {:ok, %{body: body, content_type: request_body.contentType}}
    end
  end

  @doc """
  Validates that the request body matches the operation schema
  """
  @spec matches(request_body() | nil, OpenAPI.Operation.t(), Context.t()) ::
          :ok | {:error, Exception.t()}
  def matches(request_body, operation, context)

  def matches(body, %OpenAPI.Operation{requestBody: nil}, %Context{} = _ctx) do
    if is_nil(body) do
      :ok
    else
      {:error,
       %InvalidRequest{
         message: "requestBody defined but operations doesn't accept request body"
       }}
    end
  end

  def matches(nil, %OpenAPI.Operation{requestBody: %{required: required}}, %Context{} = _ctx) do
    case required do
      true -> {:error, %InvalidRequest{message: "missing required requestBody for operation"}}
      false -> :ok
    end
  end

  def matches(request_body, %OpenAPI.Operation{} = operation, %Context{} = ctx) do
    %{body: body, content_type: content_type} = request_body

    with {:matching_body, %{schema: schema}} <-
           {:matching_body, HTTP.matching_body(content_type, operation.requestBody.content)},
         {:ok, source_description, _} =
           Context.fetch_source_description(ctx, operation.source_description_name),
         :ok <- HTTP.validate_body(body, schema, source_description) do
      :ok
    else
      {:matching_body, nil} ->
        {:error,
         %InvalidRequest{message: "no matching content-type '#{content_type}' in operation"}}

      {:error, exc} when is_exception(exc) ->
        {:error, %InvalidRequest{message: Exception.message(exc)}}
    end
  end
end
