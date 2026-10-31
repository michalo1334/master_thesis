defmodule NetworkDefense.Evaluation2Test.GraphFixtures do
  @moduledoc """
  Persisted tier graphs for Evaluation2 integration cases.

  One canonical enterprise graph is stored per tier. The graphs come from the
  existing deterministic topology generator, so a case resolves real graph
  revisions, real Host nodes, and real mission capabilities instead of
  hand-built stand-ins. Each case inserts its own graphs inside the sandbox.
  """

  alias NetworkDefense.Evaluation2.Study.Tier
  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Topology.EnterpriseTopology

  @tier_seeds %{small: 11, medium: 23, large: 37}

  @doc """
  Store one graph per tier.

  The returned map holds, per tier, the frozen graph revision identifier, one
  Host node of that revision as the foothold, one non-Host node of the same
  revision for negative cases, and one Host node of another tier for
  cross-graph cases.
  """
  def insert_tiers do
    stored = Map.new(@tier_seeds, fn {tier, seed} -> {tier, insert_tier(tier, seed)} end)

    Map.new(stored, fn {tier, inputs} ->
      {tier, Map.put(inputs, :foreign_host_node_id, foreign_host_node_id(stored, tier))}
    end)
  end

  @doc "Return the document options that declare the stored tier graphs."
  def document_opts(tiers) do
    [
      tier_graphs: Map.new(tiers, fn {tier, inputs} -> {tier, inputs.graph_revision_id} end),
      tier_footholds: Map.new(tiers, fn {tier, inputs} -> {tier, inputs.foothold_node_id} end)
    ]
  end

  @doc "Return true when one graph node is a Host node."
  def host?(%{type: type}) do
    name = to_string(type)
    name == "Host" or name == to_string(Host)
  end

  defp insert_tier(tier, seed) do
    graph = EnterpriseTopology.generate(title: "evaluation2-#{tier}", hosts: 8, seed: seed)
    {:ok, stored} = Graphs.insert(graph)
    nodes = Graph.nodes(stored)

    %{
      graph_revision_id: stored.revision_id,
      foothold_node_id: Enum.find(nodes, &host?/1).id,
      non_host_node_id: Enum.find(nodes, &(not host?(&1))).id
    }
  end

  defp foreign_host_node_id(stored, tier) do
    other_tier = Enum.find(Tier.all(), &(&1 != tier))
    stored |> Map.fetch!(other_tier) |> Map.fetch!(:foothold_node_id)
  end
end
