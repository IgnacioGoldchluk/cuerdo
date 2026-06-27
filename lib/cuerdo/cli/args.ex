defmodule Cuerdo.CLI.Args do
  @moduledoc false

  alias Cuerdo.CLI.Errors

  @doc """
  Parses the CLI arguments into ArazzoCase runner args
  """
  @spec parse([String.t()]) :: {:ok, Keyword.t()} | {:error, Exception.t()}
  def parse(args) do
    with {parsed, [], []} <- OptionParser.parse(args, strict: cli_opts()),
         {:ok, valid_args} <- NimbleOptions.validate(parsed, schema()) do
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
      report_file: [type: :string, default: "report.json"]
    ]
  end

  defp cli_opts do
    [
      num_runs: :integer,
      exclude: :string,
      only: :string,
      halt_on_error: :boolean,
      report_file: :string
    ]
  end

  defp to_runner_opts(opts) do
    opts
    |> Keyword.put(:json_schema_resolver, Cuerdo.Resolver)
    |> Keyword.put(:transform_inputs, %{})
  end

  def split_ids(ids) when is_binary(ids), do: {:ok, String.split(ids, ",")}
  def split_ids(ids), do: {:error, "expected comma-separated workflow ids, got: #{inspect(ids)}"}
end
