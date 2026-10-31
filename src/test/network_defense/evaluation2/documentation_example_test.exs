defmodule NetworkDefense.Evaluation2.DocumentationExampleTest do
  @moduledoc """
  Checks the committed operator example through the public YAML constructor.

  DOC-01: WHEN local graph identities replace the template tokens, THE constructor
  SHALL freeze the documented groups, counts, policies and model bounds.
  DOC-02: WHEN tokens remain or a Host belongs to another graph, THE constructor
  SHALL reject the example before creating an execution or scientific effect.
  DOC-03: WHEN an extra key is present, THE constructor SHALL drop it.

  Graph and revision inserts use the existing SQL Sandbox and roll back.
  These cases dispatch no Gust, optimization or simulation work.
  """

  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.{Definition, Error, Persistence, Revision}
  alias NetworkDefense.Evaluation2Test.GraphFixtures
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Simulation.Experiment

  @moduletag :integration
  @moduletag :evaluation2_integration

  @example Path.expand("../../../../docs/examples/evaluation2-study.yaml", __DIR__)
  @external_resource @example

  setup do
    tiers = GraphFixtures.insert_tiers()
    %{tiers: tiers, yaml: expand_example(tiers)}
  end

  @tag case_id: "DOC-01"
  test "freezes the committed example without starting scientific work", %{yaml: yaml} do
    counts = effect_counts()

    assert {:ok, %Revision{study_id: "example-native-study", revision: 1} = revision} =
             Study.create_revision(yaml)

    assert {:ok, %{definition: definition}} = Persistence.fetch_revision(revision)
    assert Definition.pilot_capacity(definition) == %Definition.SampleSize{plans: 2, attacks: 3}
    assert length(Definition.collection_groups(definition)) == 9
    assert length(Definition.comparisons(definition)) == 6
    assert Enum.map(definition.tiers, & &1.tier) == ["small", "medium", "large"]
    assert definition.provenance.method == "crossed-matching-betting-v1"
    assert definition.provenance.seed_contract == "evaluation2-sha256-json-v1"

    for tier <- definition.tiers do
      assert tier.mission_impact_bound == %{minimum: 0.0, maximum: 8.0}
      assert tier.budgets == [1]
      assert Enum.map(tier.alternatives, & &1.key) == [:random, :simulation_informed]
      assert Enum.at(tier.alternatives, 1).scoring.monte_carlo_trials == 2
    end

    assert Definition.effective_action_types(definition, :cvss) == [:patch_vulnerability]
    assert Definition.require_feasibility?(definition)
    assert effect_counts() == counts
  end

  @tag case_id: "DOC-02"
  test "rejects unexpanded identity tokens" do
    counts = effect_counts()

    assert {:error, %Error{category: :validation_failed}} =
             Study.create_revision(File.read!(@example))

    assert effect_counts() == counts
  end

  @tag case_id: "DOC-02"
  test "rejects a Host from a different tier graph", %{tiers: tiers} do
    yaml = expand_example(tiers, tiers.medium.foothold_node_id)
    counts = effect_counts()
    assert {:error, %Error{category: :validation_failed}} = Study.create_revision(yaml)
    assert effect_counts() == counts
  end

  @tag case_id: "DOC-03"
  test "drops an unknown field from the example", %{yaml: yaml} do
    assert {:ok, revision} = Study.create_revision(yaml <> "\noperator_note: illustrative\n")
    assert {:ok, %{definition: definition}} = Persistence.fetch_revision(revision)
    refute Map.has_key?(definition, :operator_note)
    refute Map.has_key?(definition, "operator_note")
  end

  defp expand_example(tiers, small_host \\ nil) do
    Enum.reduce(tiers, File.read!(@example), fn {tier, inputs}, yaml ->
      prefix = tier |> Atom.to_string() |> String.upcase()
      host = if tier == :small and small_host, do: small_host, else: inputs.foothold_node_id

      yaml
      |> String.replace(prefix <> "_GRAPH_REVISION", inputs.graph_revision_id)
      |> String.replace(prefix <> "_HOST_NODE", host)
    end)
  end

  defp effect_counts do
    {Repo.aggregate(Persistence.Execution, :count), Repo.aggregate(OptimizationRun, :count),
     Repo.aggregate(Experiment, :count)}
  end
end
