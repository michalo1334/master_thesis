defmodule NetworkDefense.DefenseActions.BlockReachability do
  @moduledoc false

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph

  defstruct [:edge_id, cost: 1]

  defimpl DefenseAction, for: __MODULE__ do
    alias NetworkDefense.Relationships.NetworkReachability
    def target(action), do: {Edge, action.edge_id}

    def cost(action), do: action.cost

    def eligible_types(_action), do: [NetworkReachability]

    def apply(action, graph) do
      Graph.remove_edge_by_id(graph, action.edge_id)
    end
  end
end
