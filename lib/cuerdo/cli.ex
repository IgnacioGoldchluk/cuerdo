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

  def main(args) do
    with {parsed, [], []} <- OptionParser.parse(args, strict: cli_opts()),
         {:ok, valid_args} <- NimbleOptions.validate(parsed, schema()),
         valid_args = to_runner_opts(valid_args),
         :ok <- additional_opts_validations(valid_args),
         {:ok, document} <- YamlElixir.read_from_file(parsed[:document]),
         # Clear cache before running the CLI, otherwise any updates to OpenAPI schemas
         # are not reflected
         _ = Resolution.Cache.clear(),
         {:ok, parsed_doc} <- Arazzo.Document.new(document) do
      opts = Keyword.put(valid_args, :document, document)

      results =
        Enum.flat_map(
          workflow_ids(parsed_doc, opts),
          &ArazzoCase.Runner.run_all(&1, document, opts)
        )

      ArazzoCase.Report.write(Keyword.fetch!(opts, :report_output), results, opts[:report_file])

      case results do
        [] -> System.stop(0)
        _ -> System.stop(1)
      end
    else
      {_parsed, remaining, errors} ->
        Logger.error("Invalid args: #{Enum.join(remaining ++ errors, " ")}")
        System.stop(1)

      {:error, exc} when is_exception(exc) ->
        Logger.error("Error processing arguments/document: #{Exception.message(exc)}")
        System.stop(1)
    end
  end

  defp workflow_ids(%Cuerdo.Arazzo.Document{} = document, opts) do
    workflow_ids = Enum.map(document.workflows, & &1.workflowId)

    case {opts[:only], opts[:exclude]} do
      {nil, nil} -> workflow_ids
      {nil, to_exclude} -> Enum.reject(workflow_ids, &(&1 in split_ids(to_exclude)))
      {to_keep, nil} -> split_ids(to_keep)
      {to_keep, to_exclude} -> Enum.reject(split_ids(to_keep), &(&1 in split_ids(to_exclude)))
    end
  end

  defp split_ids(ids) when is_binary(ids), do: String.split(ids, ",")

  defp schema do
    [
      document: [type: :string, required: true],
      num_runs: [type: :pos_integer, default: 20],
      halt_on_error: [type: :boolean, default: false],
      exclude: [type: :string],
      only: [type: :string],
      report_output: [type: {:custom, __MODULE__, :report_output, []}, default: :stdout],
      report_file: [type: :string]
    ]
  end

  defp cli_opts do
    [
      document: :string,
      num_runs: :integer,
      exclude: :string,
      only: :string,
      halt_on_error: :boolean,
      report_output: :string,
      report_file: :string
    ]
  end

  defp additional_opts_validations(opts) do
    validations = [&report_output_and_file/1]

    Enum.reduce_while(validations, :ok, fn func, :ok ->
      case func.(opts) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp report_output_and_file(opts) do
    case {opts[:report_output], opts[:report_file]} do
      {:stdout, nil} ->
        :ok

      {:stdout, file} when is_binary(file) ->
        Logger.warning("--report-file=#{file} for 'stdout' output. File will be ignored")

      {out, nil} ->
        {:error, %ArgumentError{message: "--report-output=#{out} missing --report-file option"}}

      _ ->
        :ok
    end
  end

  defp to_runner_opts(opts) do
    opts
    |> Keyword.put(:json_schema_resolver, Cuerdo.Resolver)
    |> Keyword.put(:transform_inputs, %{})
  end

  def report_output("json"), do: {:ok, :json}
  def report_output("stdout"), do: {:ok, :stdout}

  def report_output(other), do: {:error, "unknown --report-output=#{other}"}
end
