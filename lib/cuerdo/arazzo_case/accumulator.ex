defmodule Cuerdo.ArazzoCase.Accumulator do
  @moduledoc """
  Holds results and context for a workflow reduction check
  """
  use Agent

  alias Cuerdo.Arazzo.Context
  alias Cuerdo.Report.Result

  def start_link(%Context{} = context) do
    Agent.start_link(fn -> {[], context} end)
  end

  def put_context(pid, %Context{} = context) do
    Agent.update(pid, fn {results, _} -> {results, context} end)
  end

  def add_result(pid, %Result{} = result) do
    Agent.update(pid, fn {results, ctx} -> {[result | results], ctx} end)
  end

  def get_context(pid), do: Agent.get(pid, &elem(&1, 1))
  def get_results(pid), do: Agent.get(pid, &elem(&1, 0))
end
