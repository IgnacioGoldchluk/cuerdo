defmodule Cuerdo.CLI.Screen.Terminal do
  @moduledoc false
  @behaviour Cuerdo.CLI.Screen

  @impl Cuerdo.CLI.Screen
  def start do
    start_document()
    start_specs()
    Owl.LiveScreen.await_render()
  end

  @impl Cuerdo.CLI.Screen
  def fetched_document do
    Owl.Spinner.stop(id: :document_spinner, resolution: :ok)
  end

  @impl Cuerdo.CLI.Screen
  def fetched_specification do
    # Since this might be called multiple times. Otherwise
    # the GenServer is terminated and the 2nd call crashes
    Owl.Spinner.stop(id: :specs_spinner, resolution: :ok)
  catch
    :exit, _ -> :ok
  end

  defp start_document do
    Owl.Spinner.start(
      id: :document_spinner,
      labels: [processing: "Fetching Arazzo document", ok: "Arazzo document fetched\n"]
    )
  end

  defp start_specs do
    Owl.Spinner.start(
      id: :specs_spinner,
      labels: [processing: "Fetching OpenAPI specs", ok: "OpenAPI spec fetched\n"]
    )
  end

  @impl Cuerdo.CLI.Screen
  def start_workflows(workflow_ids, num_runs)
      when is_list(workflow_ids) and is_integer(num_runs) do
    workflow_ids
    |> pad_workflows()
    |> Enum.map(fn {workflow_id, label} ->
      Owl.ProgressBar.start(id: {:workflow, workflow_id}, label: label, total: num_runs)
    end)
  end

  @impl Cuerdo.CLI.Screen
  def completed_workflow_testcase(id), do: Owl.ProgressBar.inc(id: {:workflow, id})

  @impl Cuerdo.CLI.Screen
  def summary(results, report_file) do
    passed = Enum.filter(results, &(&1.status == :passed)) |> length()
    failed = length(results) - passed

    passed_mark = Owl.Data.tag("✓", :green) |> Owl.Data.to_chardata()
    failed_mark = Owl.Data.tag("✗", :red) |> Owl.Data.to_chardata()

    report_file =
      if failed != 0 do
        "Failures saved to #{report_file}\n"
      else
        ""
      end

    exec_time = Enum.sum_by(results, & &1.execution_time_ms)

    state =
      """

      Summary:

        #{passed_mark} PASSED: #{passed}
        #{failed_mark} FAILED: #{failed}

        in #{exec_time(exec_time)}
        #{report_file}
      """

    Owl.LiveScreen.add_block(:summary, state: state)
    Owl.LiveScreen.await_render()
  end

  defp exec_time(exec_time) when exec_time > 1000 do
    in_s = (exec_time / 1000.0) |> Float.round(2)
    "#{in_s}s"
  end

  defp exec_time(exec_time), do: "#{exec_time}ms"

  defp pad_workflows(workflow_ids) when is_list(workflow_ids) do
    longest = Enum.map(workflow_ids, &String.length/1) |> Enum.max()
    Enum.map(workflow_ids, &{&1, String.pad_trailing(&1, longest)})
  end
end
