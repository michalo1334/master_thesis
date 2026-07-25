defmodule NetworkDefense.DefenseActions.BlockReachability do
  @moduledoc false

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph

  defstruct [:edge_id, cost: 1]

  defimpl DefenseAction, for: __MODULE__ do
    def cost(action), do: action.cost

    def apply(action, graph) do
      Graph.remove_edge_by_id(graph, action.edge_id)
    end
  end
end
