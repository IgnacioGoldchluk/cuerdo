defmodule Cuerdo.OpenAPI do
  @moduledoc false

  alias Cuerdo.OpenAPI

  defguardp is_atomic(v) when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v)

  @doc """
  Returns the `Cuerdo.OpenAPI.Operation` with the `operation_id` ih the schema.
  """
  @spec fetch_operation_by_id(String.t(), any(), String.t()) ::
          {:ok, OpenAPI.Operation.t()} | {:error, any()}
  def fetch_operation_by_id(operation_id, open_api_schema, source_description_name)
      when is_binary(operation_id) do
    case fetch_operation_path(operation_id, open_api_schema) do
      {:ok, operation_path} ->
        fetch_operation_by_path(operation_path, open_api_schema, source_description_name)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Retuns the `Cuerdo.OpenAPI.Operation` at the given path in the schema.
  """
  @spec fetch_operation_by_path(String.t(), any(), String.t()) ::
          {:ok, OpenAPI.Operation.t()} | {:error, any()}
  def fetch_operation_by_path(operation_path_ptr, open_api_schema, source_description_name)
      when is_binary(operation_path_ptr) do
    json_path = RockSolid.Traversal.to_path(operation_path_ptr)
    # Because the operationPath is defined inside the method, when we fetch it we'll
    # be missing the "/path/method" of the request to make. For example a POST to
    # "/users/log-in" is represented as "#/paths/~1users~1log-in/post", but inside
    # post there is no info, therefore we have to get the method + path from the operationPath
    # itself
    [method, url_path | rest] = Enum.reverse(json_path)

    path_parameters =
      RockSolid.Traversal.get_in_schema(open_api_schema, rest ++ [url_path])
      |> Map.get("parameters", [])

    open_api_schema
    |> RockSolid.Traversal.get_in_schema(json_path)
    |> Map.merge(%{
      "method" => method,
      "path" => url_path,
      "source_description_name" => source_description_name
    })
    |> Map.update("parameters", path_parameters, &merge_parameters(&1, path_parameters))
    |> expand_refs([], open_api_schema)
    |> OpenAPI.Operation.new()
  end

  defp expand_refs(value, _rev_path, _open_api_schema) when is_atomic(value), do: value

  defp expand_refs(value, rev_path, open_api_schema) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.map(fn {element, idx} ->
      expand_refs(element, [to_string(idx) | rev_path], open_api_schema)
    end)
  end

  # Ignore because they might contain recursive paths and they're used for validating
  # request/response only
  defp expand_refs(value, ["schema", _media_type, "content", "requestBody"], _), do: value
  defp expand_refs(value, ["schema", _media_type, "content", _code, "responses"], _), do: value

  defp expand_refs(%{"$ref" => json_pointer}, rev_path, open_api_schema) do
    open_api_schema
    |> RockSolid.Traversal.get_in_schema(RockSolid.Traversal.to_path(json_pointer))
    |> expand_refs(rev_path, open_api_schema)
  end

  defp expand_refs(value, rev_path, open_api_schema) when is_map(value) do
    Map.new(value, fn {key, val} ->
      {key, expand_refs(val, [key | rev_path], open_api_schema)}
    end)
  end

  defp fetch_operation_path(operation_id, %{"paths" => paths}) do
    operations =
      for {path, methods} <- paths,
          {method, operation} <- methods,
          operation["operationId"] == operation_id do
        ["#", "paths", path, method]
      end

    case operations do
      [path] -> {:ok, RockSolid.Traversal.to_pointer(path)}
      [] -> {:error, "operationId #{operation_id} not found"}
      ops when is_list(ops) -> {:error, "multiple operationId #{operation_id} found"}
    end
  end

  defp merge_parameters(priority_parameters, overridable_parameters) do
    # Enum.uniq_by keeps the first ocurrence, we can place the priority parameters first.
    # Also "parameters" are unique by name + in fields
    Enum.uniq_by(
      priority_parameters ++ overridable_parameters,
      fn %{"name" => name, "in" => in_} -> {name, in_} end
    )
  end
end
