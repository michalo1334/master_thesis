defmodule NetworkDefense.Evaluation.StrategyFactoryTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.StrategyFactory
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, NetworkSegment, Service, Vulnerability}

  alias NetworkDefense.Optimization.{
    CvssStrategy,
    NullStrategy,
    RandomStrategy,
    SimulatedAnnealingStrategy,
    SimulationInformedStrategy,
    TopologySegmentationStrategy
  }

  alias NetworkDefense.Relationships.{Contains, HasVulnerability, Runs, SegmentReachability}

  test "builds each supported strategy kind with the same behavior and model configuration" do
    {graph, source} = graph()

    schedule = %{
      optimizer_trials: 2,
      optimizer_iterations: 2,
      entry_host_id: source.id,
      max_attempts: 1
    }

    model = %{objective: :blast_radius_only, require_pre_attack_feasibility: false}

    assert {:ok, %NullStrategy{}} = StrategyFactory.build("null", graph, schedule, 101, model)

    assert {:ok, %RandomStrategy{seed: 101}} =
             StrategyFactory.build("random", graph, schedule, 101, model)

    assert {:ok, %CvssStrategy{}} = StrategyFactory.build("cvss", graph, schedule, 101, model)

    assert {:ok, %TopologySegmentationStrategy{}} =
             StrategyFactory.build("topology_segmentation", graph, schedule, 101, model)

    assert {:ok, %SimulationInformedStrategy{} = strategy} =
             StrategyFactory.build("simulation_informed", graph, schedule, 101, model)

    assert strategy.objective == :blast_radius_only
    assert strategy.require_pre_attack_feasibility == false

    assert {:ok, %SimulatedAnnealingStrategy{} = annealing} =
             StrategyFactory.build("simulated_annealing", graph, schedule, 101, model)

    assert annealing.objective == :blast_radius_only
    assert annealing.require_pre_attack_feasibility == false
  end

  test "rejects an unknown strategy" do
    {graph, source} = graph()

    schedule = %{
      optimizer_trials: 2,
      optimizer_iterations: 2,
      entry_host_id: source.id,
      max_attempts: 1
    }

    assert {:error, "unknown strategy bogus"} =
             StrategyFactory.build("bogus", graph, schedule, 101, %{})
  end

  test "simulation_config derives the seed from a seeded strategy" do
    assert StrategyFactory.simulation_config(%RandomStrategy{seed: 42}) == %{seed: 42}
    assert StrategyFactory.simulation_config(%NullStrategy{}) == nil
  end

  test "model_settings resolves a declared variant and rejects an undeclared one" do
    manifest = %{
      "model_variants" => [
        %{"id" => "full"},
        %{"id" => "blast_only"}
      ]
    }

    assert {:ok, %{objective: :blast_radius_only}} =
             StrategyFactory.model_settings(manifest, :blast_only)

    assert {:error, "unknown model variant mission_only"} =
             StrategyFactory.model_settings(manifest, :mission_only)
  end

  defp graph do
    source = GraphFixtures.node("source", Host, %{"name" => "internet"})
    host_a = GraphFixtures.node("host-a", Host, %{"name" => "a"})
    source_segment = segment("source-segment")
    segment_a = segment("segment-a")
    service_a = service("service-a")
    vulnerability_a = vulnerability("vulnerability-a")

    graph =
      GraphFixtures.graph(
        [source_segment, segment_a, source, host_a, service_a, vulnerability_a],
        [
          GraphFixtures.edge("contains-source", source_segment, source, Contains),
          GraphFixtures.edge("contains-a", segment_a, host_a, Contains),
          GraphFixtures.edge(
            "policy-a",
            source_segment,
            segment_a,
            SegmentReachability,
            %{"protocol" => "tcp"}
          ),
          GraphFixtures.edge("runs-a", host_a, service_a, Runs),
          GraphFixtures.edge(
            "vulnerability-a",
            service_a,
            vulnerability_a,
            HasVulnerability,
            %{"required_privilege" => "none", "granted_privilege" => "user"}
          )
        ]
      )

    {graph, source}
  end

  defp segment(id), do: GraphFixtures.node(id, NetworkSegment, %{"name" => id})

  defp service(id),
    do: GraphFixtures.node(id, Service, %{"name" => id, "protocol" => "tcp", "port" => 443})

  defp vulnerability(id) do
    GraphFixtures.node(id, Vulnerability, %{
      "identifier" => id,
      "cvss" => %{
        "attack_vector" => "network",
        "attack_complexity" => "low",
        "privileges_required" => "none",
        "user_interaction" => "none",
        "scope" => "unchanged",
        "confidentiality_impact" => "high",
        "integrity_impact" => "none",
        "availability_impact" => "none"
      },
      "exploit_probability" => 1.0
    })
  end
end
