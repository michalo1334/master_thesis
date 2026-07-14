defmodule NetworkDefense.AttackerState.Graph do
  @moduledoc """
  Projects attacker footholds onto nodes in a context graph.
  """

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph

  def foothold_nodes(%Graph{} = graph, %AttackerState{} = attacker_state) do
    foothold_ids =
      attacker_state
      |> AttackerState.foothold_nodes()
      |> MapSet.new()

    graph
    |> Graph.nodes()
    |> Enum.filter(&MapSet.member?(foothold_ids, &1.id))
  end
end
