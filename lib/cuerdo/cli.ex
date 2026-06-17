defmodule Cuerdo.CLI do
  @moduledoc """
  CLI for automated test runner

  ## Options
  - `--document` - Arazzo document path.
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

  require Logger

  alias Cuerdo.Arazzo
  alias Cuerdo.ArazzoCase
  alias RockSolid.Resolution

  alias Cuerdo.CLI

  def main(args) do
    case run(args) do
      {:error, _} ->
        System.stop(1)

      {:ok, results} when is_list(results) ->
        status =
          if(Enum.reject(results, &(&1.status == :passed)) |> Enum.empty?(), do: 0, else: 1)

        System.stop(status)
    end
  end

  def run(args) do
    with {:ok, valid_args} <- CLI.Args.parse(args),
         {:ok, document} <- YamlElixir.read_from_file(valid_args[:document]),
         # Clear cache before running the CLI, otherwise any updates to OpenAPI schemas
         # are not reflected
         _ = Resolution.Cache.clear(),
         {:ok, parsed_doc} <- Arazzo.Document.new(document),
         {:ok, workflow_ids} <-
           ArazzoCase.Runner.workflow_ids(parsed_doc, valid_args[:only], valid_args[:exclude]) do
      opts = Keyword.put(valid_args, :document, document)
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
