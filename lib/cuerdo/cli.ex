defmodule Cuerdo.CLI do
  @moduledoc """
  CLI for automated test runner

  ## Usage
  Generating property-based tests from an Arazzo document
  ```bash
  ./cuerdo path/to/arazzo.yaml
  ```

  Running previously failed tests
  ```bash
  ./cuerdo replay path/to/report.json
  ```

  ## Options
  - `--max-runs` - Maximum number of cases to generate for each workflow
  - `--max-shrink-steps` - Maximum number of shrinking steps to apply when a failing case
  is found. Defaults to 0, meaning no shrinking is applied.
  - `--exclude` - Comma-separated list of workflow ids to exclude from the document
  - `--only` - Comma-separated list of workflow ids to execute from the document
  - `--report-file` - The report file destination. Defaults to `report.json`

  The options only apply when generating tests from an Arazzo document. When running
  as `replay report.json` then all the failing inputs are exercised again, ignoring
  any other command-line option.

  For more information on the options, refer to `Cuerdo.ArazzoCase`
  """
  use Application

  require Logger

  alias Cuerdo.Arazzo
  alias Cuerdo.ArazzoCase

  alias Cuerdo.CLI

  @impl true
  def start(_, _) do
    if Application.get_env(:cuerdo, :run_cli, true) do
      main(Burrito.Util.Args.argv())
    end

    Supervisor.start_link([], strategy: :one_for_one)
  end

  def main(args) do
    case run(args) do
      {:error, _} ->
        System.halt(1)

      {:ok, results} when is_list(results) ->
        status =
          if(Enum.reject(results, &(&1.status == :passed)) |> Enum.empty?(), do: 0, else: 1)

        System.halt(status)
    end
  end

  def run([]) do
    msg = "Empty arguments. Pass path/to/arazzo.yaml"
    Logger.error(msg)
    Logger.flush()
    {:error, %ArgumentError{message: msg}}
  end

  def run(["replay", replay_doc_path]) do
    CLI.Screen.start()

    with {:ok, report_document} <- File.read(replay_doc_path),
         {:ok, report_document} <- JSON.decode(report_document),
         {:ok, arazzo_document_path} <- Map.fetch(report_document, "arazzo_document"),
         {:ok, failed_results} <- Map.fetch(report_document, "results"),
         {:ok, arazzo_document} <- YamlElixir.read_from_file(arazzo_document_path),
         _ <- CLI.Screen.fetched_document(),
         {:ok, parsed_doc} <- Arazzo.Document.new(arazzo_document) do
      failures_by_workflow = CLI.Replay.failures_by_workflow_id(failed_results)

      CLI.Screen.started_workflows(Map.keys(failures_by_workflow))

      results =
        failures_by_workflow
        |> Enum.map(fn {workflow_id, failed_cases} ->
          Task.async(fn -> ArazzoCase.Runner.replay(workflow_id, failed_cases, parsed_doc) end)
        end)
        |> Task.await_many(:infinity)
        |> List.flatten()

      new_report = replay_doc_path <> "replay.json"

      ArazzoCase.Report.write(:json, results, new_report, arazzo_document_path)
      CLI.Screen.summary(results, new_report)

      {:ok, results}
    else
      {:error, exc} = error when is_exception(exc) ->
        Logger.error("Error processing arguments/document: #{Exception.message(exc)}")
        Logger.flush()
        error

      :error ->
        Logger.error("Malformed report. Expected JSON with 'arazzo_document' and 'results' keys")
        Logger.flush()
        {:error, :malformed_report}
    end
  end

  def run([document_path | args]) do
    CLI.Screen.start()

    with {:ok, valid_args} <- CLI.Args.parse(args),
         {:ok, document} <- YamlElixir.read_from_file(document_path),
         _ <- CLI.Screen.fetched_document(),
         {:ok, parsed_doc} <- Arazzo.Document.new(document),
         {:ok, workflow_ids} <-
           ArazzoCase.Runner.workflow_ids(parsed_doc, valid_args[:only], valid_args[:exclude]) do
      opts = Keyword.put(valid_args, :document, document)

      CLI.Screen.started_workflows(workflow_ids)

      results =
        workflow_ids
        |> Enum.map(fn workflow_id ->
          Task.async(fn -> ArazzoCase.Runner.run_all(workflow_id, document, opts) end)
        end)
        |> Task.await_many(:infinity)
        |> List.flatten()

      report_file = Keyword.fetch!(opts, :report_file)
      ArazzoCase.Report.write(:json, results, report_file, document_path)
      CLI.Screen.summary(results, report_file)

      {:ok, results}
    else
      {:error, exc} = error when is_exception(exc) ->
        Logger.error("Error processing arguments/document: #{Exception.message(exc)}")
        Logger.flush()
        error
    end
  end
end
