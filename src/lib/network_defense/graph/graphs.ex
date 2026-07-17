defmodule NetworkDefense.Graph.Graphs do
  @moduledoc """
  Loads persisted graphs into their in-memory adjacency representation.
  """

  import Ecto.Query

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
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

  def list_summaries do
    graphs =
      Graph
      |> order_by([graph], asc: graph.title)
      |> select([graph], {graph.id, graph.title})
      |> Repo.all()

    if graphs == [] do
      []
    else
      graph_ids = Enum.map(graphs, &elem(&1, 0))

      node_counts =
        from(n in Node,
          where: n.graph_id in ^graph_ids,
          group_by: n.graph_id,
          select: {n.graph_id, count(n.id)}
        )
        |> Repo.all()
        |> Map.new()

      edge_counts =
        from(e in Edge,
          where: e.graph_id in ^graph_ids,
          group_by: e.graph_id,
          select: {e.graph_id, count(e.id)}
        )
        |> Repo.all()
        |> Map.new()

      Enum.map(graphs, fn {id, title} ->
        %{
          id: id,
          title: title,
          nodeCount: Map.get(node_counts, id, 0),
          edgeCount: Map.get(edge_counts, id, 0)
        }
      end)
    end
  end

  defp hydrate_graph(%Graph{} = graph) do
    graph = Repo.preload(graph, [:nodes, :edges], force: true)
    Graph.hydrate(graph, graph.nodes, graph.edges)
  end
end
