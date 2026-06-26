defmodule Cuerdo.ArazzoCase.Runner do
  @moduledoc false
  alias Cuerdo.Arazzo
  alias Cuerdo.Arazzo.Context
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

  def run_all(workflow_id, arazzo_document, opts) do
    print_start_workflow(workflow_id)

    with {:ok, %Context{} = ctx} <-
           Context.from_document(arazzo_document, resolver: opts[:json_schema_resolver]),
         {:ok, workflow} <- Arazzo.Document.fetch_workflow(ctx.document, workflow_id),
         {:ok, schema} <- Arazzo.build_schema(workflow.inputs, ctx),
         {:ok, generator} <- generator(schema, workflow_id, opts) do
      halt_on_error? = Keyword.fetch!(opts, :halt_on_error)
      num_runs = Keyword.fetch!(opts, :num_runs)

      generator
      |> Enum.take(num_runs)
      |> Enum.with_index(1)
      |> Enum.reduce_while({[], ctx}, fn {workflow_inputs, idx}, {results, ctx} ->
        Logger.debug("#{workflow_id} #{idx}/#{num_runs}")

        Context.clear_api_calls(ctx)

        case run_workflow(workflow_inputs, workflow_id, ctx) do
          {time_ms, {:ok, updated_ctx}} ->
            result = %Result{
              workflow_id: workflow_id,
              inputs: workflow_inputs,
              execution_time_ms: time_ms,
              status: :passed
            }

            print_result(:passed)
            {:cont, {[result | results], Context.transfer_cache(ctx, updated_ctx)}}

          {time_ms, {:error, exc}} ->
            result = %Result{
              workflow_id: workflow_id,
              inputs: workflow_inputs,
              execution_time_ms: time_ms,
              status: :failed,
              reason: exc,
              logs: HAR.to_har(exc.api_calls)
            }

            print_result(:failed)

            new_acc = {[result | results], ctx}
            if(halt_on_error?, do: {:halt, new_acc}, else: {:cont, new_acc})
        end
      end)
      |> then(&elem(&1, 0))
      |> Enum.reverse()
    else
      {:error, exc} when is_exception(exc) ->
        Logger.error("generating tests for #{workflow_id}: #{Exception.message(exc)}")
        print_result(:error)
        [%Result{workflow_id: workflow_id, status: :error, reason: exc, execution_time_ms: 0}]
    end
  end

  # Runs timed workflow
  defp run_workflow(workflow_inputs, workflow_id, ctx) do
    :timer.tc(fn -> Arazzo.run_workflow(workflow_inputs, workflow_id, ctx) end, :millisecond)
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

  defp print_start_workflow(workflow_id) do
    if Application.get_env(:cuerdo, :stdio_enabled, true) do
      IO.write("\n#{workflow_id}: ")
    end
  end

  defp print_result(status) do
    if Application.get_env(:cuerdo, :stdio_enabled, true) do
      case status do
        :passed -> IO.write(IO.ANSI.format([:green, "."]))
        :failed -> IO.write(IO.ANSI.format([:red, "F"]))
        :error -> IO.write(IO.ANSI.format([:red, "E"]))
      end
    end
  end
end
