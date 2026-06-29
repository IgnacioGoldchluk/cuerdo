defmodule Cuerdo.ArazzoCase.Runner do
  @moduledoc false
  alias Cuerdo.Arazzo
  alias Cuerdo.Arazzo.Context
  alias Cuerdo.ArazzoCase.Accumulator
  alias Cuerdo.ArazzoCase.Result
  alias Cuerdo.HAR

  require Logger

  @doc """
  Returns the workflow ids to execute.

  If the final list contains a workflow that does not exist then returns an argument error
  """
  @spec workflow_ids(Arazzo.Document.t(), [String.t()] | nil, [String.t()] | nil) ::
          {:ok, [String.t()]} | {:error, Exception.t()}
  def workflow_ids(%Arazzo.Document{} = document, to_keep, to_exclude) do
    all_ids = Enum.map(document.workflows, & &1.workflowId)

    workflow_ids =
      case {to_keep, to_exclude} do
        {nil, nil} -> all_ids
        {nil, to_exclude} -> Enum.reject(all_ids, &(&1 in to_exclude))
        {to_keep, nil} -> to_keep
        {to_keep, to_exclude} -> for id <- to_keep, id not in to_exclude, do: id
      end

    case Enum.filter(workflow_ids, &(not Enum.member?(all_ids, &1))) do
      [] -> {:ok, workflow_ids}
      ids -> {:error, %ArgumentError{message: "invalid workflow ids: #{Enum.join(ids, ", ")}"}}
    end
  end

  def replay(workflow_id, failed_inputs, document) do
    case Context.from_document(document, resolver: Cuerdo.Resolver) do
      {:ok, ctx} ->
        {:ok, agent} = Accumulator.start_link(ctx)

        failed_inputs
        |> Enum.map(fn failed_input -> check_workflow(failed_input, workflow_id, agent) end)
        |> Enum.all?(&match?({:ok, _}, &1))
        |> case do
          true -> Cuerdo.CLI.Screen.completed_workflow(workflow_id, :passed)
          false -> Cuerdo.CLI.Screen.completed_workflow(workflow_id, :failed)
        end

        Accumulator.get_results(agent) |> Enum.reverse()

      {:error, exc} when is_exception(exc) ->
        [%Result{workflow_id: workflow_id, status: :error, reason: exc, execution_time_ms: 0}]
    end
  end

  def run_all(workflow_id, arazzo_document, opts) do
    with {:ok, %Context{} = ctx} <-
           Context.from_document(arazzo_document, resolver: opts[:json_schema_resolver]),
         {:ok, workflow} <- Arazzo.Document.fetch_workflow(ctx.document, workflow_id),
         {:ok, schema} <- Arazzo.build_schema(workflow.inputs, ctx),
         {:ok, generator} <- generator(schema, workflow_id, opts) do
      max_runs = Keyword.fetch!(opts, :max_runs)
      max_shrink = Keyword.fetch!(opts, :max_shrink_steps)
      seed = :os.timestamp()

      check_opts = [max_runs: max_runs, max_shrinking_steps: max_shrink, initial_seed: seed]
      {:ok, agent} = Accumulator.start_link(ctx)

      # We could do something with the :original_failure and :shrunk_failure later
      case StreamData.check_all(generator, check_opts, &check_workflow(&1, workflow_id, agent)) do
        {:ok, _} ->
          Cuerdo.CLI.Screen.completed_workflow(workflow_id, :passed)

          Accumulator.get_results(agent)

        {:error, _} ->
          Cuerdo.CLI.Screen.completed_workflow(workflow_id, :failed)
          Accumulator.get_results(agent)
      end
      |> Enum.reverse()
    else
      {:error, exc} when is_exception(exc) ->
        Logger.error("generating tests for #{workflow_id}: #{Exception.message(exc)}")
        [%Result{workflow_id: workflow_id, status: :error, reason: exc, execution_time_ms: 0}]
    end
  end

  # Runs timed workflow
  defp run_workflow(workflow_inputs, workflow_id, ctx) do
    :timer.tc(fn -> Arazzo.run_workflow(workflow_inputs, workflow_id, ctx) end, :millisecond)
  end

  defp check_workflow(workflow_inputs, workflow_id, agent) do
    ctx = Accumulator.get_context(agent)

    case run_workflow(workflow_inputs, workflow_id, ctx) do
      {time_ms, {:ok, updated_ctx}} ->
        result = %Result{
          workflow_id: workflow_id,
          inputs: workflow_inputs,
          execution_time_ms: time_ms,
          status: :passed
        }

        Cuerdo.CLI.Screen.completed_workflow_testcase(workflow_id)
        new_ctx = Context.transfer_cache(ctx, updated_ctx)
        Accumulator.add_result(agent, result)
        Accumulator.put_context(agent, new_ctx)

        {:ok, nil}

      {time_ms, {:error, exc}} ->
        result = %Result{
          workflow_id: workflow_id,
          inputs: workflow_inputs,
          execution_time_ms: time_ms,
          status: :failed,
          reason: exc,
          logs: HAR.to_har(exc.api_calls)
        }

        Cuerdo.CLI.Screen.completed_workflow_testcase(workflow_id)
        Accumulator.add_result(agent, result)
        {:error, workflow_inputs}
    end
  end

  defp generator(schema, workflow_id, opts) do
    base = RockSolid.from_schema(schema, resolver: opts[:json_schema_resolver])

    case Map.get(opts[:transform_inputs], workflow_id) do
      nil -> base
      {mod, func, args} -> StreamData.bind(base, fn val -> apply(mod, func, [val] ++ args) end)
    end
    |> then(&{:ok, &1})
  rescue
    exc -> {:error, exc}
  end
end
