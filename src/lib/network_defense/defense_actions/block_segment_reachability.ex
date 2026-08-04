defmodule NetworkDefense.DefenseActions.BlockSegmentReachability do
  @moduledoc false

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph

  defstruct [:edge_id, cost: 1]

  defimpl DefenseAction, for: __MODULE__ do
    alias NetworkDefense.Relationships.SegmentReachability
    def target(action), do: {Edge, action.edge_id}
    def with_target_id(action, target_id), do: %{action | edge_id: target_id}

    def cost(action), do: action.cost

    def eligible_types(_action), do: [SegmentReachability]

    def apply(action, graph) do
      Graph.remove_edge_by_id(graph, action.edge_id)
    end
  end
end
