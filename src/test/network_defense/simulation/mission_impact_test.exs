defmodule NetworkDefense.Simulation.MissionImpactTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, MissionCapability}
  alias NetworkDefense.Relationships.Supports
  alias NetworkDefense.Simulation.MissionImpact

  test "marks a capability down when fewer than its required supports remain" do
    primary = GraphFixtures.node("primary", Host, %{"name" => "primary"})
    replica = GraphFixtures.node("replica", Host, %{"name" => "replica"})
    capability = capability("orders", 8.0, 2)

    graph =
      GraphFixtures.graph(
        [primary, replica, capability],
        [
          GraphFixtures.edge("supports-primary", primary, capability, Supports),
          GraphFixtures.edge("supports-replica", replica, capability, Supports)
        ]
      )

    assert MissionImpact.final(graph, []) == 0.0
    assert MissionImpact.final(graph, [primary.id]) == 8.0
  end

  test "models one remaining support as sufficient when k is one" do
    primary = GraphFixtures.node("primary", Host, %{"name" => "primary"})
    replica = GraphFixtures.node("replica", Host, %{"name" => "replica"})
    capability = capability("orders", 8.0, 1)

    graph =
      GraphFixtures.graph(
        [primary, replica, capability],
        [
          GraphFixtures.edge("supports-primary", primary, capability, Supports),
          GraphFixtures.edge("supports-replica", replica, capability, Supports)
        ]
      )

    assert MissionImpact.final(graph, [primary.id]) == 0.0
    assert MissionImpact.final(graph, [primary.id, replica.id]) == 8.0
  end

  defp capability(id, impact_weight, min_operational_support) do
    GraphFixtures.node(id, MissionCapability, %{
      "name" => id,
      "impact_weight" => impact_weight,
      "min_operational_support" => min_operational_support
    })
  end
end
