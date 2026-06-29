defmodule Cuerdo.CLI.Replay do
  @moduledoc false
  @doc """
  Groups all failed inputs by workflow id
  """
  def failures_by_workflow_id(results) do
    results
    |> Enum.filter(&(&1["status"] in ["failed", "error"]))
    |> Enum.reduce(%{}, fn %{"workflow_id" => workflow_id, "inputs" => inputs}, acc ->
      Map.update(acc, workflow_id, [inputs], &(&1 ++ [inputs]))
    end)
  end
end
