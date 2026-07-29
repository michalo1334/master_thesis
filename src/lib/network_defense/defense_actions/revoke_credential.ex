defmodule NetworkDefense.DefenseActions.RevokeCredential do
  @moduledoc false

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node

  defstruct [:credential_id, cost: 1]

  defimpl DefenseAction, for: __MODULE__ do
    alias NetworkDefense.Nodes.Credential
    def target(action), do: {Node, action.credential_id}

    def with_target_id(action, target_id), do: %{action | credential_id: target_id}

    def cost(action), do: action.cost

    def eligible_types(_action), do: [Credential]

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
