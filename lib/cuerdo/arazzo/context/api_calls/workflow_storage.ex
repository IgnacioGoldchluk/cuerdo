defmodule Cuerdo.Arazzo.Context.APICalls.WorkflowStorage do
  @moduledoc false
  use Agent

  alias Cuerdo.Arazzo.Context.APICalls

  @key :api_calls_storage

  @doc """
  Resets any existing API workflow storage
  """
  def reset do
    case agent_pid() do
      nil ->
        {:ok, pid} = start_link()
        Process.put(@key, pid)
        :ok

      _ ->
        clear()
    end
  end

  defp agent_pid do
    case Process.get(@key) do
      nil ->
        {:ok, pid} = start_link()
        Process.put(@key, pid)
        pid

      pid when is_pid(pid) ->
        pid
    end
  end

  def start_link do
    Agent.start_link(fn -> [] end)
  end

  def store(%APICalls{} = new_calls) do
    Agent.update(agent_pid(), fn api_calls -> [new_calls | api_calls] end)
  end

  def clear, do: Agent.update(agent_pid(), fn _ -> [] end)
  def get_all, do: Agent.get(agent_pid(), &Enum.reverse(& 1))

  def get_http_call(query_path) when is_list(query_path) do
    Agent.get(agent_pid(), fn state ->
      Enum.find(state, fn %APICalls{path: path} -> List.ends_with?(path, query_path) end)
    end)
  end
end
