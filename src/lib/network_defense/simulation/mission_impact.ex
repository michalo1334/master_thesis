defmodule NetworkDefense.Simulation.MissionImpact do
  @moduledoc false

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Nodes.MissionCapability

  @spec final(Graph.t(), [String.t()]) :: float()
  def final(graph, foothold_ids) do
    graph
    |> capability_statuses(foothold_ids)
    |> Enum.reduce(0.0, fn capability, impact ->
      if capability.down?, do: impact + capability.impact_weight, else: impact
    end)
  end

  @spec capability_statuses(Graph.t(), [String.t()]) :: [map()]
  def capability_statuses(graph, foothold_ids) do
    compromised = MapSet.new(foothold_ids)

    graph
    |> Graph.nodes()
    |> Enum.filter(&(&1.type == MissionCapability))
    |> Enum.map(fn capability ->
      supporting_host_ids = Graph.supporting_host_ids(graph, capability.id)

      compromised_support_count =
        Enum.count(supporting_host_ids, &MapSet.member?(compromised, &1))

      supporting_host_count = length(supporting_host_ids)

      %{
        capability_id: capability.id,
        name: capability.data.name,
        impact_weight: capability.data.impact_weight,
        supporting_host_count: supporting_host_count,
        compromised_support_count: compromised_support_count,
        down?:
          supporting_host_count - compromised_support_count <
            capability.data.min_operational_support
      }
    end)
  end
end
