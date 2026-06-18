defmodule Cuerdo.Traversal do
  @moduledoc false

  @type execution_path :: [String.t() | non_neg_integer()]

  defguardp is_api_call(r) when r in ["request", "response"]

  alias Cuerdo.Arazzo.{Context, Document}
  alias Cuerdo.Errors.InvalidExpression

  # Converts a runtime expression like $sourceDescriptions.name.url to
  # ["sourceDescriptions", "name", "url"]
  defp to_path(runtime_expression)
  defp to_path("$" <> expression), do: String.split(expression, ".")

  @doc """
  Returns the value at the given JSON path and/or JSON pointer.

  ## Arguments
  - `json_path` either the JSON path in the form `["sourceDescriptions", "name", "url"]`
  or a tuple containing a JSON pointer `{["inputs", "person"], "#/name"}`
  - `reversed_path` the location of the JSON path. This is required because some JSON paths
  are context dependent, such as `$statusCode`, which refers to the status code of the response
  for the current step
  - `context` - `t:Cuerdo.Arazzo.Context.t/0`
  """
  @spec fetch_value(String.t() | {String.t(), String.t()}, [String.t()], Context.t()) ::
          {:ok, term()} | {:error, Exception.t()}
  def fetch_value(json_path, reversed_path, context) do
    path =
      case json_path do
        {runtime_path, pointer} -> {to_path(runtime_path), pointer}
        runtime_path when is_binary(runtime_path) -> to_path(runtime_path)
      end

    case do_fetch_value(path, reversed_path, context) do
      {:ok, value} ->
        {:ok, value}

      {:error, message} when is_binary(message) ->
        {:error, %InvalidExpression{expression: json_path, message: message}}

      {:error, exc} when is_exception(exc) ->
        {:error, %InvalidExpression{expression: json_path, message: Exception.message(exc)}}
    end
  end

  # Special case because `sourceDescriptions` are referenced by name
  defp do_fetch_value(["sourceDescriptions", name, field], _, %Context{} = ctx) do
    with {:ok, source_description} <- Document.fetch_source_description(ctx.document, name),
         {:ok, field_atom} <- field_to_atom(field),
         {:ok, value} <- Map.fetch(source_description, field_atom) do
      {:ok, value}
    else
      :error -> {:error, "field #{field} not in source description #{name}"}
      other -> other
    end
  end

  defp do_fetch_value(["inputs", value], reversed_path, %Context{} = ctx) do
    # We know `inputs` cannot be a runtime expression because we populate them asap
    # It's always a defined value
    with {:ok, workflow_id} <- workflow_id(reversed_path, ctx),
         inputs when not is_nil(inputs) <- get_in(ctx.inputs, [workflow_id, value]) do
      {:ok, inputs}
    else
      nil ->
        {:ok, workflow_id} = workflow_id(reversed_path, ctx)
        {:error, "input #{value} not set for workflow #{workflow_id}"}

      error ->
        error
    end
  end

  defp do_fetch_value(
         {["inputs", _val] = json_path, json_pointer},
         reversed_path,
         %Context{} = ctx
       ) do
    with {:ok, base} <- do_fetch_value(json_path, reversed_path, ctx),
         {:ok, value} <-
           RockSolid.Traversal.fetch_in_schema(base, RockSolid.Traversal.to_path(json_pointer)) do
      {:ok, value}
    end
  end

  defp do_fetch_value(["outputs", value], reversed_path, %Context{} = ctx) do
    # Same as `inputs`, we populate the outputs asap, they cannot reference another
    # runtime expression
    with {:ok, workflow_id} <- workflow_id(reversed_path, ctx),
         {:ok, workflow_outputs} <- Map.fetch(ctx.outputs, workflow_id),
         {:ok, output} <- Map.fetch(workflow_outputs, value) do
      {:ok, output}
    else
      :error ->
        {:ok, workflow_id} = workflow_id(reversed_path, ctx)
        {:error, "no output #{value} in workflow #{workflow_id}"}

      error ->
        error
    end
  end

  defp do_fetch_value(
         {["outputs", _val] = json_path, json_pointer},
         reversed_path,
         %Context{} = ctx
       ) do
    with {:ok, base} <- do_fetch_value(json_path, reversed_path, ctx),
         {:ok, value} <-
           RockSolid.Traversal.fetch_in_schema(base, RockSolid.Traversal.to_path(json_pointer)) do
      {:ok, value}
    end
  end

  defp do_fetch_value(["steps", name, "outputs", value], reversed_path, %Context{} = ctx) do
    with {:ok, workflow_id} <- workflow_id(reversed_path, ctx),
         # Guaranteed to exist
         steps_outputs = ctx.outputs[workflow_id][:steps],
         {:ok, step_outputs} <- Map.fetch(steps_outputs, name),
         {:ok, output_value} <- Map.fetch(step_outputs, value) do
      {:ok, output_value}
    else
      :error -> {:error, "no output #{value} in step #{name}"}
      error -> error
    end
  end

  defp do_fetch_value(
         {["steps", _name, "outputs", _val] = json_path, json_pointer},
         reversed_path,
         %Context{} = ctx
       ) do
    with {:ok, base} <- do_fetch_value(json_path, reversed_path, ctx),
         {:ok, value} <-
           RockSolid.Traversal.fetch_in_schema(
             base,
             RockSolid.Traversal.to_path(json_pointer)
           ) do
      {:ok, value}
    end
  end

  defp do_fetch_value(["url"], reversed_path, %Context{} = ctx) do
    case request(reversed_path, ctx) do
      {:ok, %Req.Request{url: url}} -> {:ok, to_string(url)}
      error -> error
    end
  end

  defp do_fetch_value(["statusCode"], reversed_path, %Context{} = ctx) do
    case response(reversed_path, ctx) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      error -> error
    end
  end

  defp do_fetch_value(["method"], reversed_path, %Context{} = ctx) do
    # Since method in Req is :get, :post, etc. they convert to GET, POST
    case request(reversed_path, ctx) do
      {:ok, %Req.Request{method: method}} -> {:ok, to_string(method) |> String.upcase()}
      error -> error
    end
  end

  defp do_fetch_value(["request", "path", name], reversed_path, %Context{} = ctx) do
    with {:ok, name_atom} <- field_to_atom(name),
         {:ok, request} <- request(reversed_path, ctx),
         {:ok, path_params} <- Map.fetch(request.options, :path_params),
         {:ok, param_value} <- Keyword.fetch(path_params, name_atom) do
      {:ok, param_value}
    else
      :error -> {:error, "invalid request path: #{name}"}
    end
  end

  defp do_fetch_value([r, "header", name], reversed_path, %Context{} = ctx)
       when is_api_call(r) do
    normalized_header = String.downcase(name)

    with {:ok, api_call} <- api_call(r, reversed_path, ctx),
         headers = Req.get_headers_list(api_call),
         {^normalized_header, value} <-
           List.keyfind(headers, normalized_header, 0) do
      {:ok, value}
    else
      nil ->
        {:ok, api_call} = api_call(r, reversed_path, ctx)
        headers = Req.get_headers_list(api_call) |> Enum.map_join(", ", &elem(&1, 0))
        {:error, "header #{normalized_header} missing. Available headers are #{headers}"}

      error ->
        error
    end
  end

  defp do_fetch_value([r, "body"], reversed_path, %Context{} = ctx) when is_api_call(r) do
    case api_call(r, reversed_path, ctx) do
      {:ok, %{body: body}} -> {:ok, body}
      error -> error
    end
  end

  defp do_fetch_value({[r, "body"] = json_path, json_pointer}, reversed_path, %Context{} = ctx)
       when is_api_call(r) do
    with {:ok, base} <- do_fetch_value(json_path, reversed_path, ctx),
         {:ok, value} <-
           RockSolid.Traversal.fetch_in_schema(base, RockSolid.Traversal.to_path(json_pointer)) do
      {:ok, value}
    end
  end

  defp do_fetch_value(["components", type, value], _, %Context{} = ctx) do
    with components when not is_nil(components) <- ctx.document.components,
         {:ok, atom_type} <- field_to_atom(type),
         {:ok, component} <- Map.fetch(components, atom_type),
         {:ok, component_value} <- Map.fetch(component, value) do
      {:ok, component_value}
    else
      :error -> {:error, "invalid component: #{type}.#{value}"}
      error -> error
    end
  end

  defp do_fetch_value(
         {["components", _type, _key] = json_path, json_pointer},
         rev_path,
         %Context{} = ctx
       ) do
    with {:ok, base} <- do_fetch_value(json_path, rev_path, ctx),
         {:ok, value} <-
           RockSolid.Traversal.fetch_in_schema(base, RockSolid.Traversal.to_path(json_pointer)) do
      {:ok, value}
    end
  end

  defp do_fetch_value(_pointer, _rev_path, _context) do
    {:error, "does not match any valid expression"}
  end

  defp workflow_id([idx, "workflows" | _], %Context{} = ctx) when is_integer(idx) do
    case Enum.fetch(ctx.document.workflows, idx) do
      :error -> {:error, "invalid workflow index #{idx}"}
      {:ok, workflow} -> {:ok, workflow.workflowId}
    end
  end

  defp workflow_id([_ | rest], %Context{} = ctx), do: workflow_id(rest, ctx)

  defp step_id([idx, "steps" | _], workflow_id, %Context{} = ctx) when is_integer(idx) do
    with {:ok, %{steps: steps}} <- Document.fetch_workflow(ctx.document, workflow_id),
         {:ok, %{stepId: step_id}} <- Enum.fetch(steps, idx) do
      {:ok, step_id}
    else
      :error -> {:error, "invalid step index #{idx}"}
      {:error, exc} = error when is_exception(exc) -> error
    end
  end

  defp api_call("request", reversed_path, ctx), do: request(reversed_path, ctx)
  defp api_call("response", reversed_path, ctx), do: response(reversed_path, ctx)

  defp request(reversed_path, %Context{} = ctx) do
    with {:ok, workflow_id} <- workflow_id(reversed_path, ctx),
         {:ok, step_id} <- step_id(reversed_path, workflow_id, ctx),
         %{request: %Req.Request{} = request} <- get_in(ctx.api_calls, [workflow_id, step_id]) do
      {:ok, request}
    else
      %{request: nil} -> {:error, "request not set in #{path_to_string(reversed_path)}"}
      {:error, exc} = error when is_exception(exc) -> error
      {:error, msg} when is_binary(msg) -> {:error, msg}
    end
  end

  defp response(reversed_path, %Context{} = ctx) do
    with {:ok, workflow_id} <- workflow_id(reversed_path, ctx),
         {:ok, step_id} <- step_id(reversed_path, workflow_id, ctx),
         %{response: %Req.Response{} = response} <- get_in(ctx.api_calls, [workflow_id, step_id]) do
      {:ok, response}
    else
      %{request: nil} -> {:error, "request not set in #{path_to_string(reversed_path)}"}
      {:error, exc} = error when is_exception(exc) -> error
      {:error, msg} when is_binary(msg) -> {:error, msg}
    end
  end

  defp path_to_string(reversed_path), do: reversed_path |> Enum.reverse() |> Enum.join(".")

  defp field_to_atom(field) when is_binary(field) do
    {:ok, String.to_existing_atom(field)}
  rescue
    _ -> {:error, "invalid field: #{field}"}
  end
end
