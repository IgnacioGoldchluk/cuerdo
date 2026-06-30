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
      max_runs: [type: :pos_integer, default: 20],
      max_shrink_steps: [type: :non_neg_integer, default: 0],
      exclude: [type: {:custom, __MODULE__, :split_ids, []}],
      only: [type: {:custom, __MODULE__, :split_ids, []}],
      report_file: [type: :string, default: "report.json"],
      ui: [type: {:in, ["rich", "basic", "none"]}, default: "rich"]
    ]
  end

  defp cli_opts do
    [
      max_runs: :integer,
      max_shrink_steps: :integer,
      exclude: :string,
      only: :string,
      report_file: :string,
      ui: :string
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
