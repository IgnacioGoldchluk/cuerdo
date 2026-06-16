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
    results_by_workflow_id = Enum.group_by(results, & &1.workflow_id)
    exec_time = Enum.sum_by(results, & &1.execution_time_ms)

    longest_id = results_by_workflow_id |> Map.keys() |> Enum.map(&String.length/1) |> Enum.max()

    msg = """
    Arazzo document test suite summary

    Total execution time: #{exec_time}ms

    #{Enum.map_join(results_by_workflow_id, "\n", &to_summary_line(&1, longest_id))}
    """

    IO.puts(msg)
  end

  defp to_summary_line({workflow_id, results}, longest_id) do
    total = length(results)
    total_passed = Enum.count(results, &(&1.status == :passed))

    "#{String.pad_trailing(workflow_id, longest_id)}: #{total_passed}/#{total} cases passed"
  end
end
