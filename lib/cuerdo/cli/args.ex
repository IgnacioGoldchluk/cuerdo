defmodule Cuerdo.CLI.Args do
  @moduledoc false

  alias Cuerdo.CLI.Errors

  require Logger

  @doc """
  Parses the CLI arguments into ArazzoCase runner args
  """
  @spec parse([String.t()]) :: {:ok, Keyword.t()} | {:error, Exception.t()}
  def parse(args) do
    with {parsed, [], []} <- OptionParser.parse(args, strict: cli_opts()),
         {:ok, valid_args} <- NimbleOptions.validate(parsed, schema()),
         :ok <- additional_opts_validations(valid_args) do
      {:ok, to_runner_opts(valid_args)}
    else
      {_parsed, remaining, errors} -> {:error, %Errors.UnexpectedArgs{args: remaining ++ errors}}
      {:error, exc} when is_exception(exc) -> {:error, exc}
    end
  end

  defp schema do
    [
      num_runs: [type: :pos_integer, default: 20],
      halt_on_error: [type: :boolean, default: false],
      exclude: [type: {:custom, __MODULE__, :split_ids, []}],
      only: [type: {:custom, __MODULE__, :split_ids, []}],
      report_output: [type: {:custom, __MODULE__, :report_output, []}, default: :stdout],
      report_file: [type: :string]
    ]
  end

  defp cli_opts do
    [
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
    |> Keyword.put_new(:report_output, :stdout)
  end

  def report_output("json"), do: {:ok, :json}
  def report_output("stdout"), do: {:ok, :stdout}
  # From the default case
  def report_output(:stdout), do: {:ok, :stdout}

  def report_output(other) when is_binary(other), do: {:error, "unknown --report-output=#{other}"}

  def split_ids(ids) when is_binary(ids), do: {:ok, String.split(ids, ",")}
  def split_ids(ids), do: {:error, "expected comma-separated workflow ids, got: #{inspect(ids)}"}
end
