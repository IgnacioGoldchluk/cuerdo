defmodule Cuerdo.Arazzo.HTTP do
  @moduledoc """
  Validations for request and responses in Arazzo workflows
  """

  alias Cuerdo.Errors.InvalidRequest

  @doc """
  Validates the body matches the schema in the context of the source description.

  Source description must be an OpenAPI map
  """
  @spec validate_body(any(), any(), map(), module()) :: :ok | {:error, Exception.t()}
  def validate_body(body, schema, source_description, resolver)

  def validate_body(_, %{"components" => _}, _, _) do
    {:error, %InvalidRequest{message: "operation schema contains ambiguous key: 'components'"}}
  end

  def validate_body(request_body, operation_schema, openapi_schema, resolver) do
    schema =
      case Map.get(openapi_schema, "components") do
        nil -> operation_schema
        components -> Map.put(operation_schema, "components", components)
      end

    with {:ok, root_schema} <- JSV.build(schema, resolver: resolver),
         {:ok, _} <- JSV.validate(request_body, root_schema) do
      :ok
    else
      # `requestBody` could be a JSON-encoded string representing an object. If it
      # fails we have to try decoding too. Otherwise return the original error
      {:error, %JSV.ValidationError{} = e} when is_binary(request_body) ->
        case JSON.decode(request_body) do
          {:ok, decoded} ->
            validate_body(decoded, operation_schema, openapi_schema, resolver)

          _ ->
            {:error, e}
        end

      other_error ->
        other_error
    end
  end

  @doc """
  Returns the matching operation request or response body for the given content type, or
  nil if no content type matches
  """
  @spec matching_body(String.t(), map()) :: map() | nil
  def matching_body(content_type, operation_request_bodies) when is_binary(content_type) do
    content_type
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.find_value(&do_matching_body(&1, operation_request_bodies))
  end

  defp do_matching_body(content_type, operation_request_bodies) when is_binary(content_type) do
    case String.split(content_type, "/") do
      [type, subtype] ->
        # Full "application/json" has priority, then "application/*", then "*/json" and
        # finally "*/*" wildcard
        candidates_priority = [content_type, "#{type}/*", "*/#{subtype}", "*/*"]
        Enum.find_value(candidates_priority, &Map.get(operation_request_bodies, &1))

      _ ->
        # Not in the form of "application/json" or any other media type, ignore
        nil
    end
  end
end
