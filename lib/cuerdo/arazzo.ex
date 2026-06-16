defmodule Cuerdo.Arazzo do
  @moduledoc """
  Arazzo workflows runner and validation.
  """

  alias Cuerdo.Arazzo.{
    Context,
    Criterion,
    Document,
    Parameter,
    Request,
    RequestBody,
    Response,
    RuntimeExpression,
    Step,
    Workflow
  }

  alias Cuerdo.Errors.ExecutionError

  alias Cuerdo.OpenAPI

  @spec run_workflow(any(), String.t(), map() | Context.t()) ::
          {:ok, Context.t()} | {:error, ExecutionError.t()}
  def run_workflow(workflow_inputs, workflow_id, %Context{} = context) do
    do_run_workflow(workflow_inputs, workflow_id, context, [workflow_id])
  end

  @doc """
  Runs the workflowId with the given inputs from the Arazzo document.

  Returns `{:ok, context}` on success with each step requests and responses,
  or an `{:error, reason}`.

  ## Options

  - `:resolver` - The JSON Schema resolver to use for validating workflow inputs and request/response schemas.
  See [JSV Resolvers](`e:jsv:resolvers.html`)
  """
  @spec run_workflow(any(), String.t(), map(), Keyword.t()) ::
          {:ok, Context.t()} | {:error, Exception.t()}
  def run_workflow(workflow_inputs, workflow_id, document, opts \\ []) when is_map(document) do
    case Context.from_document(document, opts) do
      {:ok, %Context{} = ctx} -> run_workflow(workflow_inputs, workflow_id, ctx)
      {:error, exc} when is_exception(exc) -> {:error, ExecutionError.wrap(exc, [workflow_id])}
    end
  end

  defp do_run_workflow(workflow_inputs, workflow_id, document_or_context, execution_path) do
    with {:ok, %Context{} = ctx} <- Context.from_document(document_or_context),
         {:ok, idx} <- Document.fetch_workflow_index(ctx.document, workflow_id),
         ctx = Context.put_inputs(ctx, workflow_id, workflow_inputs),
         base_rev_path = [idx, "workflows"],
         workflow = Document.workflow(ctx.document, workflow_id),
         :ok <- Workflow.validate_inputs(workflow_inputs, workflow, ctx),
         {:ok, %Context{} = ctx} <-
           run_steps(workflow.steps, base_rev_path, ctx, execution_path, workflow.parameters),
         {:ok, %Context{} = ctx} <- update_workflow_outputs(ctx, workflow_id, base_rev_path) do
      {:ok, ctx}
    else
      {:error, error} when is_exception(error) ->
        {:error, ExecutionError.wrap(error, execution_path)}
    end
  end

  defp run_steps(steps, base_rev_path, ctx, execution_path, workflow_parameters) do
    steps
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, ctx}, fn {step, step_idx}, {:ok, ctx} ->
      step_id = step.stepId
      step_path = [step_idx, "steps" | base_rev_path]
      step_execution_path = execution_path ++ [step_id]

      case run_step(step, step_path, ctx, step_execution_path, workflow_parameters) do
        {:ok, new_ctx} ->
          {:cont, {:ok, new_ctx}}

        {:error, e} when is_exception(e) ->
          {:halt, {:error, ExecutionError.wrap(e, step_execution_path)}}
      end
    end)
  end

  defp run_step(
         %Step{workflowId: nil} = step,
         [_step_idx, "steps", workflow_idx, "workflows"] = rev_path,
         %Context{} = ctx,
         execution_path,
         workflow_parameters
       ) do
    workflow = Enum.fetch!(ctx.document.workflows, workflow_idx)
    workflow_id = workflow.workflowId

    %Step{
      stepId: step_id,
      parameters: step_parameters,
      requestBody: request_body,
      successCriteria: success_criteria
    } = step

    with {:ok, operation, ctx} <- OpenAPI.Operation.fetch(step, ctx),
         {:ok, base_url} <- Request.fetch_base_url(operation.source_description_name, ctx),
         {:ok, parameters} <-
           Parameter.resolve(step_parameters ++ workflow_parameters, rev_path, ctx),
         {:ok, request_body} <- RequestBody.resolve(request_body, rev_path, ctx),
         :ok <- RequestBody.matches(request_body, operation, ctx),
         :ok <- Parameter.all_present(parameters, operation.parameters),
         request = Step.build_request(base_url, parameters, request_body, operation, step.timeout),
         {request, %Req.Response{} = response} <- Req.Request.run_request(request),
         ctx_req_resp = put_request_response_step(ctx, workflow_id, step_id, request, response),
         {:ok, new_ctx} <- update_step_outputs(ctx_req_resp, workflow_id, step_id, rev_path),
         :ok <- Criterion.evaluate_many(success_criteria, rev_path, new_ctx),
         :ok <- Response.matches(response, operation, new_ctx) do
      # There is no need for successActions and failureActions for now. Those might be useful
      # for Arazzo workflows and documentation but not for testing. Tests must never have
      # branching
      {:ok, new_ctx}
    else
      {%Req.Request{}, exception} ->
        {:error, ExecutionError.wrap(exception, execution_path)}

      {:error, exc} when is_exception(exc) ->
        {:error, ExecutionError.wrap(exc, execution_path)}
    end
  end

  defp run_step(
         %Step{workflowId: "$sourceDescriptions" <> _ = workflow_id} = step,
         [_step_idx, "steps", workflow_idx, "workflows"] = rev_path,
         %Context{} = ctx,
         execution_path,
         _workflow_parameters
       ) do
    original_workflow_id =
      ctx.document.workflows |> Enum.fetch!(workflow_idx) |> Map.fetch!(:workflowId)

    with {:ok, workflow_inputs} <- to_workflow_inputs(step.parameters, rev_path, ctx),
         {:name, ["$sourceDescriptions", source_description_name, remote_workflow_id]} <-
           {:name, String.split(workflow_id, ".")},
         {:ok, arazzo_document, updated_ctx} <-
           Context.fetch_source_description(ctx, source_description_name),
         {:ok, workflow_ctx} <- Context.from_base(updated_ctx, arazzo_document),
         {:ok, remote_workflow_ctx} <-
           do_run_workflow(
             workflow_inputs,
             remote_workflow_id,
             workflow_ctx,
             execution_path ++ [remote_workflow_id]
           ) do
      new_ctx =
        remote_workflow_ctx
        |> Context.workflow_outputs(remote_workflow_id)
        |> Enum.reduce(updated_ctx, fn {key, value}, ctx ->
          Context.put_step_output(ctx, original_workflow_id, step.stepId, key, value)
        end)
        |> Context.merge_cache(remote_workflow_ctx)

      {:ok, new_ctx}
    else
      {:error, exc} when is_exception(exc) ->
        {:error, ExecutionError.wrap(exc, execution_path)}
    end
  end

  defp run_step(
         %Step{workflowId: workflow_id} = step,
         [_step_idx, "steps", workflow_idx, "workflows"] = rev_path,
         %Context{} = ctx,
         execution_path,
         # We can ignore parameters for nested workflows
         _workflow_parameters
       ) do
    original_workflow_id =
      ctx.document.workflows |> Enum.fetch!(workflow_idx) |> Map.fetch!(:workflowId)

    # We can safely use the same context because we only need the workflow outputs, and the workflow
    # that is going to run overrides everything anyway, there is no need to create a new one.
    with {:ok, workflow_inputs} <- to_workflow_inputs(step.parameters, rev_path, ctx),
         {:ok, %Context{} = workflow_ctx} <-
           do_run_workflow(workflow_inputs, workflow_id, ctx, execution_path ++ [workflow_id]) do
      new_ctx =
        workflow_ctx
        |> Context.workflow_outputs(workflow_id)
        |> Enum.reduce(ctx, fn {key, value}, ctx ->
          Context.put_step_output(ctx, original_workflow_id, step.stepId, key, value)
        end)
        |> Context.merge_cache(workflow_ctx)

      {:ok, new_ctx}
    else
      {:error, exc} when is_exception(exc) ->
        {:error, ExecutionError.wrap(exc, execution_path)}
    end
  end

  defp to_workflow_inputs(parameters, reversed_path, %Context{} = ctx) do
    Enum.reduce_while(
      parameters,
      {:ok, Map.new()},
      fn %{name: name, value: value, in: nil}, {:ok, acc} ->
        case RuntimeExpression.resolve(value, reversed_path, ctx) do
          {:error, _} = error -> {:halt, error}
          {:ok, value} -> {:cont, {:ok, Map.put(acc, name, value)}}
        end
      end
    )
  end

  @doc false
  @spec update_workflow_outputs(Context.t(), String.t(), [String.t()]) ::
          {:ok, Context.t()} | {:error, Exception.t()}
  def update_workflow_outputs(%Context{} = ctx, workflow_id, rev_path) do
    ctx
    |> Context.workflow_outputs(workflow_id)
    |> Enum.reduce_while({:ok, ctx}, fn {output_key, {:unresolved, ref}}, {:ok, ctx} ->
      case RuntimeExpression.resolve(ref, rev_path, ctx) do
        {:ok, value} ->
          {:cont, {:ok, Context.put_workflow_output(ctx, workflow_id, output_key, value)}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  @doc false
  @spec update_step_outputs(Context.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, Context.t()} | {:error, Exception.t()}
  def update_step_outputs(%Context{} = ctx, workflow_id, step_id, rev_path) do
    ctx
    |> Context.step_outputs(workflow_id, step_id)
    |> Enum.reduce_while({:ok, ctx}, fn {output_key, {:unresolved, ref}}, {:ok, ctx} ->
      case RuntimeExpression.resolve(ref, rev_path, ctx) do
        {:ok, value} ->
          {:cont, {:ok, Context.put_step_output(ctx, workflow_id, step_id, output_key, value)}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  @doc false
  def put_request_response_step(%Context{} = ctx, workflow_id, step_id, request, response) do
    ctx
    |> Context.put_step_request(workflow_id, step_id, request |> with_decoded_body())
    |> Context.put_step_response(workflow_id, step_id, response)
  end

  defp with_decoded_body(%Req.Request{body: nil} = request), do: request

  defp with_decoded_body(%Req.Request{body: body} = request) do
    %{request | body: JSON.decode!(body)}
  end

  @doc false
  # Builds the workflow input schema for the given context, replacing all runtime expressions.
  def build_schema(inputs, context)

  def build_schema(%{"components" => _} = inputs, %Context{} = _ctx) do
    raise ArgumentError, "inputs schema has ambiguous 'components' keys: #{inspect(inputs)}"
  end

  def build_schema(inputs, %Context{} = ctx) do
    inputs
    |> Map.put("components", %{})
    |> put_in(["components", "inputs"], Document.component_inputs(ctx.document))
    |> RuntimeExpression.resolve([], ctx)
  end
end
