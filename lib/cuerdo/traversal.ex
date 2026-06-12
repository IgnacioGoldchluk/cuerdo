defmodule Cuerdo.Traversal do
  @moduledoc false

  @type execution_path :: [String.t() | non_neg_integer()]

  defguardp is_api_call(r) when r in ["request", "response"]

  alias Cuerdo.Arazzo.{Context, Document, SourceDescription}
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

    {:ok, do_get_value(path, reversed_path, context)}
  rescue
    # Not ideal but there are too many things that can go wrong here
    _ -> {:error, %InvalidExpression{expression: json_path, stacktrace: __STACKTRACE__}}
  end

  # Special case because `sourceDescriptions` are referenced by name
  defp do_get_value(["sourceDescriptions", name, field], _, %Context{} = ctx) do
    Enum.find(ctx.document.sourceDescriptions, fn %SourceDescription{} = source_description ->
      source_description.name == name
    end)
    |> Map.get(String.to_existing_atom(field))
  end

  defp do_get_value(["inputs", value], reversed_path, %Context{} = ctx) do
    # We know `inputs` cannot be a runtime expression because we populate them asap
    # It's always a defined value
    workflow_id = workflow_id(reversed_path, ctx)
    ctx.inputs[workflow_id][value]
  end

  defp do_get_value({["inputs", _val] = json_path, json_pointer}, reversed_path, %Context{} = ctx) do
    json_path
    |> do_get_value(reversed_path, ctx)
    |> RockSolid.Traversal.get_in_schema(RockSolid.Traversal.to_path(json_pointer))
  end

  defp do_get_value(["outputs", value], reversed_path, %Context{} = ctx) do
    # Same as `inputs`, we populate the outputs asap, they cannot reference another
    # runtime expression
    workflow_id = workflow_id(reversed_path, ctx)
    ctx.outputs[workflow_id][value]
  end

  defp do_get_value(
         {["outputs", _val] = json_path, json_pointer},
         reversed_path,
         %Context{} = ctx
       ) do
    json_path
    |> do_get_value(reversed_path, ctx)
    |> RockSolid.Traversal.get_in_schema(RockSolid.Traversal.to_path(json_pointer))
  end

  defp do_get_value(["steps", name, "outputs", value], reversed_path, %Context{} = ctx) do
    workflow_id = workflow_id(reversed_path, ctx)
    ctx.outputs[workflow_id][:steps][name][value]
  end

  defp do_get_value(
         {["steps", _name, "outputs", _val] = json_path, json_pointer},
         reversed_path,
         %Context{} = ctx
       ) do
    json_path
    |> do_get_value(reversed_path, ctx)
    |> RockSolid.Traversal.get_in_schema(RockSolid.Traversal.to_path(json_pointer))
  end

  defp do_get_value(["url"], reversed_path, %Context{} = ctx) do
    request(reversed_path, ctx).url |> to_string()
  end

  defp do_get_value(["statusCode"], reversed_path, %Context{} = ctx) do
    response(reversed_path, ctx).status
  end

  defp do_get_value(["method"], reversed_path, %Context{} = ctx) do
    # Since method in Req is :get, :post, etc. they convert to GET, POST
    request(reversed_path, ctx).method |> to_string() |> String.upcase()
  end

  defp do_get_value(["request", "path", name], reversed_path, %Context{} = ctx) do
    param_name = String.to_existing_atom(name)
    request(reversed_path, ctx).options.path_params[param_name]
  end

  defp do_get_value([r, "header", name], reversed_path, %Context{} = ctx)
       when is_api_call(r) do
    normalized_header = String.downcase(name)

    {^normalized_header, value} =
      case r do
        "request" -> request(reversed_path, ctx)
        "response" -> response(reversed_path, ctx)
      end
      |> Req.get_headers_list()
      |> List.keyfind!(normalized_header, 0)

    value
  end

  defp do_get_value([r, "body"], reversed_path, %Context{} = ctx) when is_api_call(r) do
    case r do
      "request" -> request(reversed_path, ctx)
      "response" -> response(reversed_path, ctx)
    end
    |> Map.get(:body)
  end

  defp do_get_value({[r, "body"] = json_path, json_pointer}, reversed_path, %Context{} = ctx)
       when is_api_call(r) do
    json_path
    |> do_get_value(reversed_path, ctx)
    |> RockSolid.Traversal.get_in_schema(RockSolid.Traversal.to_path(json_pointer))
  end

  defp do_get_value(["components", type, value], _, %Context{} = ctx) do
    ctx.document.components
    |> Map.get(String.to_existing_atom(type))
    |> Map.get(value)
  end

  defp do_get_value(
         {["components", _type, _key] = json_path, json_pointer},
         rev_path,
         %Context{} = ctx
       ) do
    json_path
    |> do_get_value(rev_path, ctx)
    |> RockSolid.Traversal.get_in_schema(RockSolid.Traversal.to_path(json_pointer))
  end

  defp workflow_id([idx, "workflows" | _], %Context{} = ctx) when is_integer(idx) do
    Enum.fetch!(ctx.document.workflows, idx).workflowId
  end

  defp workflow_id([_ | rest], %Context{} = ctx), do: workflow_id(rest, ctx)

  defp step_id([idx, "steps" | _], workflow_id, %Context{} = ctx) when is_integer(idx) do
    ctx.document
    |> Document.workflow(workflow_id)
    |> Map.get(:steps)
    |> Enum.fetch!(idx)
    |> Map.get(:stepId)
  end

  defp request(reversed_path, %Context{} = ctx) do
    workflow_id = workflow_id(reversed_path, ctx)
    step_id = step_id(reversed_path, workflow_id, ctx)
    ctx.api_calls[workflow_id][step_id].request
  end

  defp response(reversed_path, %Context{} = ctx) do
    workflow_id = workflow_id(reversed_path, ctx)
    step_id = step_id(reversed_path, workflow_id, ctx)
    ctx.api_calls[workflow_id][step_id].response
  end
end
