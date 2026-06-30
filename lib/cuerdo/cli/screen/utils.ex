defmodule Cuerdo.CLI.Screen.Utils do
  @moduledoc false

  def version do
    Application.spec(:cuerdo) |> Keyword.fetch!(:vsn) |> to_string()
  end

  def summary(results) do
    total = length(results)
    passed = Enum.filter(results, &(&1.status == :passed)) |> length()
    failed = total - passed
    exec_time = Enum.sum_by(results, & &1.execution_time_ms)
    "#{passed} passed · #{failed} failed · #{total} total · #{exec_time(exec_time)}"
  end

  defp exec_time(exec_time) when exec_time > 1000 do
    in_s = (exec_time / 1000.0) |> Float.round(2)
    "#{in_s}s"
  end

  defp exec_time(exec_time), do: "#{exec_time}ms"
end
