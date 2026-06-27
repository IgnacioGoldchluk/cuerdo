defmodule Cuerdo.CLI do
  @moduledoc """
  CLI for automated test runner

  ## Options
  - `--num-runs` - The number of cases to generate for each workflow
  - `--exclude` - Comma-separated list of workflow ids to exclude from the document
  - `--only` - Comma-separated list of workflow ids to execute from the document
  - `--halt-on-error` (flag) - Whether to stop execution on the first failure of each workflow
  - `--report-file` - The report file destination. Defaults to `report.json`

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

  def run([document_path | args]) do
    CLI.Screen.start()

    with {:ok, valid_args} <- CLI.Args.parse(args),
         {:ok, document} <- YamlElixir.read_from_file(document_path),
         _ <- CLI.Screen.fetched_document(),
         {:ok, parsed_doc} <- Arazzo.Document.new(document),
         {:ok, workflow_ids} <-
           ArazzoCase.Runner.workflow_ids(parsed_doc, valid_args[:only], valid_args[:exclude]) do
      opts = Keyword.put(valid_args, :document, document)

      CLI.Screen.start_workflows(workflow_ids, opts[:num_runs])
      results = Enum.flat_map(workflow_ids, &ArazzoCase.Runner.run_all(&1, document, opts))

      report_file = Keyword.fetch!(opts, :report_file)
      ArazzoCase.Report.write(:json, results, report_file)
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
