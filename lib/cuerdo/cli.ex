defmodule Cuerdo.CLI do
  @moduledoc """
  CLI for automated test runner

  ## Options
  - `--num-runs` - The number of cases to generate for each workflow
  - `--exclude` - Comma-separated list of workflow ids to exclude from the document
  - `--only` - Comma-separated list of workflow ids to execute from the document
  - `--halt-on-error` (flag) - Whether to stop execution on the first failure of each workflow
  - `--report-output` - The test suite report output. Defaults to `stdout`. Supported values
  are `stdout` and `json`
  - `--report-file` - The report file destination. Mandatory if `--report-output` is different
  from `stdout`

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
      Logger.info("Running Cuerdo Arazzo runner")
      main(Burrito.Util.Args.argv())
    end

    Supervisor.start_link([], strategy: :one_for_one)
  end

  def main(args) do
    case run(args) do
      {:error, _} ->
        Logger.flush()
        System.halt(1)

      {:ok, results} when is_list(results) ->
        status =
          if(Enum.reject(results, &(&1.status == :passed)) |> Enum.empty?(), do: 0, else: 1)

        Logger.flush()
        System.halt(status)
    end
  end

  def run([]) do
    msg = "Empty arguments. Pass path/to/arazzo.yaml"
    Logger.error(msg)
    {:error, %ArgumentError{message: msg}}
  end

  def run([document_path | args]) do
    with {:ok, valid_args} <- CLI.Args.parse(args),
         {:ok, document} <- YamlElixir.read_from_file(document_path),
         {:ok, parsed_doc} <- Arazzo.Document.new(document),
         {:ok, workflow_ids} <-
           ArazzoCase.Runner.workflow_ids(parsed_doc, valid_args[:only], valid_args[:exclude]) do
      opts = Keyword.put(valid_args, :document, document)
      Logger.info("Executing workflows: #{Enum.join(workflow_ids, ", ")}")
      results = Enum.flat_map(workflow_ids, &ArazzoCase.Runner.run_all(&1, document, opts))

      ArazzoCase.Report.write(Keyword.fetch!(opts, :report_output), results, opts[:report_file])

      {:ok, results}
    else
      {:error, exc} = error when is_exception(exc) ->
        Logger.error("Error processing arguments/document: #{Exception.message(exc)}")
        error
    end
  end
end
