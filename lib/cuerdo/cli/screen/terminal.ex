defmodule Cuerdo.CLI.Screen.Terminal do
  @moduledoc false
  @behaviour Cuerdo.CLI.Screen

  use Agent

  alias Cuerdo.CLI.Screen
  alias Cuerdo.Report.Result

  def start_link do
    Agent.start_link(fn -> %{workflows: %{}, documents: []} end, name: __MODULE__)
  end

  def init(_) do
    {:ok, %{workflows: %{}, documents: []}}
  end

  @impl Cuerdo.CLI.Screen
  def start do
    start_link()
    Owl.LiveScreen.add_block(:version, state: "Started Cuerdo #{Screen.Utils.version()}")
    start_document()
    start_specs()
    Owl.LiveScreen.await_render()
  end

  @impl Cuerdo.CLI.Screen
  def fetched_document do
    Owl.Spinner.stop(id: :document_spinner, resolution: :ok)
  end

  @impl Cuerdo.CLI.Screen
  def fetched_specification(url) do
    prev_fetched = Agent.get(__MODULE__, & &1[:documents])
    new = (prev_fetched ++ [url]) |> Enum.uniq()
    Owl.LiveScreen.update(:openapi_specifications, new)
    Agent.cast(__MODULE__, fn state -> Map.put(state, :documents, new) end)
  end

  defp start_document do
    processing = faint("Fetching Arazzo document")
    ok = faint("Arazzo document fetched")
    Owl.Spinner.start(id: :document_spinner, labels: [processing: processing, ok: ok])
  end

  defp start_specs do
    Owl.LiveScreen.add_block(:openapi_specifications, state: [], render: &render_openapi_specs/1)
  end

  @impl Cuerdo.CLI.Screen
  def started_workflows(workflow_ids) when is_list(workflow_ids) do
    workflow_info = faint("Collected #{length(workflow_ids)} workflows")
    Owl.LiveScreen.add_block(:collection_info, state: workflow_info)

    Enum.each(workflow_ids, fn workflow_id ->
      Owl.Spinner.start(
        id: {:workflow, workflow_id},
        label: yellow(workflow_id),
        frames: [ok: green("✓ "), error: red("✗ ")]
      )
    end)

    Agent.update(__MODULE__, fn state ->
      Map.put(state, :workflows, Map.from_keys(workflow_ids, %{status: :running, cases: 0}))
    end)
  end

  @impl Cuerdo.CLI.Screen
  def completed_workflow_testcase(workflow_id) do
    cases = Agent.get(__MODULE__, &get_in(&1, [:workflows, workflow_id, :cases])) + 1

    new_label =
      case cases do
        1 -> yellow("#{workflow_id} · 1 case")
        more -> yellow("#{workflow_id} · #{more} cases")
      end

    Owl.Spinner.update_label(id: {:workflow, workflow_id}, label: new_label)

    Agent.cast(__MODULE__, fn state -> put_in(state, [:workflows, workflow_id, :cases], cases) end)
  end

  @impl Cuerdo.CLI.Screen
  def completed_workflow(workflow_id, final_state) do
    workflow_state =
      Agent.get(__MODULE__, fn state -> get_in(state, [:workflows, workflow_id]) end)

    {resolution, label} =
      case {final_state, workflow_state[:cases]} do
        {:passed, 1} -> {:ok, green("#{workflow_id} · 1 case")}
        {:passed, c} -> {:ok, green("#{workflow_id} · #{c} cases")}
        {:failed, 1} -> {:error, red("#{workflow_id} · 1 case")}
        {:failed, c} -> {:error, red("#{workflow_id} · #{c} cases")}
      end

    Agent.cast(__MODULE__, fn state ->
      put_in(state, [:workflows, workflow_id, :status], final_state)
    end)

    Owl.Spinner.stop(id: {:workflow, workflow_id}, resolution: resolution, label: label)
  end

  @impl Cuerdo.CLI.Screen
  def summary(results, report_file) do
    summary = Screen.Utils.summary(results)

    case Enum.find(results, &(&1.status == :failed)) do
      nil ->
        :ok

      %Result{} = result ->
        first_failed_msg = result |> Result.format_message() |> faint()

        first_failed = """

        Failure Detail
        #{first_failed_msg}
        Report saved to #{report_file}
        """

        Owl.LiveScreen.add_block(:failure_summary, state: first_failed)
    end

    Owl.LiveScreen.add_block(:summary, state: summary)
    Owl.LiveScreen.await_render()
  end

  defp faint(text) when is_binary(text) do
    Owl.Data.tag(text, [:faint]) |> Owl.Data.to_chardata()
  end

  defp yellow(text) when is_binary(text) do
    Owl.Data.tag(text, [:yellow]) |> Owl.Data.to_chardata()
  end

  defp green(text) when is_binary(text) do
    Owl.Data.tag(text, [:green]) |> Owl.Data.to_chardata()
  end

  defp red(text) when is_binary(text) do
    Owl.Data.tag(text, [:red]) |> Owl.Data.to_chardata()
  end

  defp render_openapi_specs(specs_urls) when is_list(specs_urls) do
    """
    OpenAPI documents:
    #{Enum.map_join(specs_urls, "\n", fn url -> faint("- #{url} - fetched") end)}

    """
    |> faint()
    |> Owl.Data.to_chardata()
  end
end
