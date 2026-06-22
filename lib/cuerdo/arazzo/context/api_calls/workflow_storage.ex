defmodule Cuerdo.Arazzo.Context.APICalls.WorkflowStorage do
  @moduledoc false
  use Agent

  alias Cuerdo.Arazzo.Context.APICalls

  def start_link do
    Agent.start_link(fn -> [] end)
  end

  def store(pid, %APICalls{} = new_calls) do
    Agent.update(pid, fn api_calls -> [new_calls | api_calls] end)
  end

  def clear(pid), do: Agent.update(pid, fn _ -> [] end)

  def get_all(pid), do: Agent.get(pid, &Enum.reverse(& 1))
end
