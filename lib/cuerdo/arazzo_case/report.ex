defmodule Cuerdo.ArazzoCase.Report do
  @moduledoc false

  alias Cuerdo.ArazzoCase.Result

  @type report :: :stdout | :json

  @spec write(report(), list[Result.t()], String.t() | nil) :: :ok | {:error, any()}
  def write(:stdout, results, _), do: stdout(results)
  def write(:json, results, filename), do: json(filename, results)

  defp json(filename, results) when is_binary(filename) and is_list(results) do
    File.write(filename, JSON.encode!(results))
  end

  defp stdout(results) when is_list(results) do
    summaries = Enum.group_by(results, & &1.workflow_id) |> Enum.map(&to_summary/1)
    exec_time = Enum.sum_by(results, & &1.execution_time_ms)

    header = ["Workflow ID", "PASSED", "TOTAL"]

    msg = """

    Arazzo document test suite summary

    Total execution time: #{exec_time}ms

    #{TableRex.quick_render!(summaries, header)}
    """

    IO.puts(msg)
  end

  defp to_summary({workflow_id, results}) do
    total = length(results)
    passed = Enum.count(results, &(&1.status == :passed))
    [workflow_id, passed, total]
  end
end
