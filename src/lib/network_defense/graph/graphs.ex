defmodule NetworkDefense.Graph.Graphs do
  @moduledoc """
  Loads persisted graphs into their in-memory adjacency representation.
  """

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Repo

  def load(id) do
    Graph
    |> Repo.get(id)
    |> hydrate_graph_if_found()
  end

  def load!(id) do
    Graph
    |> Repo.get!(id)
    |> hydrate_graph()
  end

  defp hydrate_graph_if_found(nil), do: nil
  defp hydrate_graph_if_found(graph), do: hydrate_graph(graph)

  defp hydrate_graph(%Graph{} = graph) do
    graph = Repo.preload(graph, [:nodes, :edges], force: true)
    Graph.hydrate(graph, graph.nodes, graph.edges)
  end
end
