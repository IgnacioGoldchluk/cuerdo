defmodule Cuerdo.Graph do
  @moduledoc """
  Functions for working with graphs
  """

  @doc """
  Returns whether the list of `{workflow_id: [depends_on]}` contains a cycle

  ## Examples

      iex> Cuerdo.Graph.cyclic?(%{})
      false

      iex> Cuerdo.Graph.cyclic?(%{foo: [:bar], baz: [:bar]})
      false

      iex> Cuerdo.Graph.cyclic?(%{})
  """
  # Switch to `:graph` after updating to OTP29
  @spec cyclic?(%{term() => [term()]}) :: boolean()
  def cyclic?(dependencies) do
    graph = :digraph.new()

    Enum.each(dependencies, fn {workflow_id, depends_on} ->
      :digraph.add_vertex(graph, workflow_id)

      Enum.each(depends_on, fn dependency ->
        :digraph.add_vertex(graph, dependency)
        :digraph.add_edge(graph, workflow_id, dependency)
      end)
    end)

    not :digraph_utils.is_acyclic(graph)
  end
end
