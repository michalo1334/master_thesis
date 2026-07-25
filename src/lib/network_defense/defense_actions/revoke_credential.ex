defmodule NetworkDefense.DefenseActions.RevokeCredential do
  @moduledoc false

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph

  defstruct [:credential_id, cost: 1]

  defimpl DefenseAction, for: __MODULE__ do
    def cost(action), do: action.cost

    def apply(action, graph) do
      # Remove ALL AuthenticatesTo edges outgoing from this credential
      edges = Graph.edges(graph)

      to_remove =
        Enum.filter(edges, fn edge ->
          edge.from_id == action.credential_id and
            edge.type == NetworkDefense.Relationships.AuthenticatesTo
        end)

      Enum.reduce(to_remove, graph, fn edge, graph_acc ->
        Graph.remove_edge_by_id(graph_acc, edge.id)
      end)
    end
  end
end
