defmodule NetworkDefense.Evaluation2.RevisionCreationTest do
  @moduledoc """
  Revision creation against stored tier graphs.

  Cases: INPUT-02 (graph and Host foothold resolution before insertion),
  INPUT-03 (a duplicate declared identity is a conflict and preserves the frozen
  definition), and the persist/reload evidence of one new-format definition.

  The persisted definition is read back through the internal persistence owner
  because the supported read paths start an execution.

  Both Repo targets must use the isolated local test database. The cases run
  inside the sandbox:

      mix test test/network_defense/evaluation2/revision_creation_test.exs
  """

  use NetworkDefense.DataCase, async: false

  import NetworkDefense.Evaluation2Test.FoundationFixtures

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.Error, as: PersistenceError
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefense.Evaluation2Test.GraphFixtures
  alias NetworkDefense.Topology.EnterpriseTopology

  @moduletag :integration
  @moduletag :evaluation2_integration

  @identity %Revision{study_id: "example-study", revision: 1}

  setup do
    tiers = GraphFixtures.insert_tiers()
    %{tiers: tiers, document_opts: GraphFixtures.document_opts(tiers)}
  end

  describe "INPUT-02 graph resolution" do
    test "freezes the declared identity and resolves every tier input", %{document_opts: opts} do
      assert {:ok, %Revision{study_id: "example-study", revision: 1}} =
               Study.create_revision(valid_yaml(opts))

      assert {:ok, %{definition: definition}} = Persistence.fetch_revision(@identity)

      assert Enum.map(definition.tiers, &tier_name/1) == ["small", "medium", "large"]

      expected_graphs =
        Map.new(opts[:tier_graphs], fn {tier, id} -> {to_string(tier), id} end)

      assert graph_revision_ids(definition) == expected_graphs

      expected_footholds =
        Map.new(opts[:tier_footholds], fn {tier, id} -> {to_string(tier), id} end)

      assert foothold_node_ids(definition) == expected_footholds
    end

    test "rejects a foothold that belongs to another graph", %{tiers: tiers, document_opts: opts} do
      footholds =
        Map.put(opts[:tier_footholds], :small, tiers.small.foreign_host_node_id)

      yaml = valid_yaml(Keyword.put(opts, :tier_footholds, footholds))

      assert {:error, %Error{category: :validation_failed}} = Study.create_revision(yaml)
      assert {:error, %PersistenceError{kind: :not_found}} = Persistence.fetch_revision(@identity)
    end

    test "rejects a foothold that is not a Host node", %{tiers: tiers, document_opts: opts} do
      footholds = Map.put(opts[:tier_footholds], :small, tiers.small.non_host_node_id)
      yaml = valid_yaml(Keyword.put(opts, :tier_footholds, footholds))

      assert {:error, %Error{category: :validation_failed}} = Study.create_revision(yaml)
      assert {:error, %PersistenceError{kind: :not_found}} = Persistence.fetch_revision(@identity)
    end

    test "rejects a graph revision that does not exist", %{document_opts: opts} do
      graphs = Map.put(opts[:tier_graphs], :small, Ecto.UUID.generate())
      yaml = valid_yaml(Keyword.put(opts, :tier_graphs, graphs))

      assert {:error, %Error{category: :validation_failed}} = Study.create_revision(yaml)
      assert {:error, %PersistenceError{kind: :not_found}} = Persistence.fetch_revision(@identity)
    end

    test "rejects a malformed document without inserting a revision", %{document_opts: _opts} do
      assert {:error, %Error{category: :validation_failed}} = Study.create_revision("study: [")
      assert {:error, %PersistenceError{kind: :not_found}} = Persistence.fetch_revision(@identity)
    end
  end

  test "INPUT-01 stores a positive integer precision target as a scientific number", %{
    document_opts: opts
  } do
    yaml = String.replace(valid_yaml(opts), "target_half_width: 0.05", "target_half_width: 1")
    assert {:ok, _} = Study.create_revision(yaml)
    assert {:ok, %{definition: stored}} = Persistence.fetch_revision(@identity)
    assert stored.pilot.precision.target_half_width == 1.0
  end

  test "INPUT-01 freezes the configured measurement label through persistence", %{
    document_opts: opts
  } do
    previous = Application.get_env(:network_defense, :measured_environment_revision)

    Application.put_env(
      :network_defense,
      :measured_environment_revision,
      "foundation-test-environment"
    )

    on_exit(fn ->
      Application.put_env(:network_defense, :measured_environment_revision, previous)
    end)

    assert {:ok, _} = Study.create_revision(valid_yaml(opts))
    assert {:ok, %{definition: stored}} = Persistence.fetch_revision(@identity)
    assert stored.provenance.environment_label == "foundation-test-environment"
  end

  @tag case_id: "POLICY-01"
  test "rejects required infeasibility before insertion and permits explicit unrestricted input",
       %{document_opts: opts} do
    alias NetworkDefense.Graph.Graph

    opts =
      with_model_weights(opts, [2.0, 7.0], fn graph ->
        graph
        |> Graph.edges()
        |> Enum.filter(&(&1.type == NetworkDefense.Relationships.SegmentReachability))
        |> Enum.reduce(graph, fn edge, g -> Graph.remove_edge_by_id(g, edge.id) end)
      end)

    yaml = valid_yaml(opts)
    assert {:error, %Error{category: :validation_failed}} = Study.create_revision(yaml)
    assert {:error, %PersistenceError{kind: :not_found}} = Persistence.fetch_revision(@identity)

    assert {:ok, _} =
             Study.create_revision(
               String.replace(yaml, "feasibility: required", "feasibility: unrestricted")
             )
  end

  @tag case_id: "POLICY-01"
  test "rejects topology segmentation without required reachability before insertion", %{
    document_opts: opts
  } do
    alias NetworkDefense.Graph.Graph

    opts =
      with_model_weights(opts, [2.0, 7.0], fn graph ->
        graph
        |> Graph.edges()
        |> Enum.filter(&(&1.type == NetworkDefense.Relationships.SegmentReachability))
        |> Enum.reduce(graph, fn edge, g -> Graph.remove_edge_by_id(g, edge.id) end)
      end)

    yaml =
      valid_yaml(opts)
      |> String.replace("feasibility: required", "feasibility: unrestricted")
      |> String.replace("strategy: random", "strategy: topology_segmentation")

    assert {:error, %Error{category: :validation_failed}} = Study.create_revision(yaml)
    assert {:error, %PersistenceError{kind: :not_found}} = Persistence.fetch_revision(@identity)
  end

  describe "frozen model bound" do
    @tag case_id: "NUM-06"
    test "sums positive model weights before any observation exists", %{document_opts: opts} do
      opts = with_model_weights(opts, [2.0, 7.0])
      assert {:ok, _} = Study.create_revision(valid_yaml(opts))
      assert {:ok, %{definition: definition}} = Persistence.fetch_revision(@identity)
      assert hd(definition.tiers).mission_impact_bound == %{minimum: 0.0, maximum: 9.0}
      assert Repo.aggregate(Persistence.EvidenceSnapshot, :count) == 0
    end

    @tag case_id: "NUM-06"
    test "rejects an overflowing model sum before storing the definition", %{document_opts: opts} do
      opts = with_model_weights(opts, [1.0e308, 1.0e308])

      assert {:error, %Error{category: :validation_failed}} =
               Study.create_revision(valid_yaml(opts))

      assert {:error, %PersistenceError{kind: :not_found}} = Persistence.fetch_revision(@identity)
    end

    @tag case_id: "NUM-06"
    test "freezes structural zero when the graph has no mission capabilities", %{
      document_opts: opts
    } do
      opts = with_model_weights(opts, [])
      assert {:ok, _} = Study.create_revision(valid_yaml(opts))
      assert {:ok, %{definition: definition}} = Persistence.fetch_revision(@identity)
      assert hd(definition.tiers).mission_impact_bound == %{minimum: 0.0, maximum: 0.0}
    end

    test "is finite and positive for every resolved tier", %{document_opts: opts} do
      assert {:ok, _revision} = Study.create_revision(valid_yaml(opts))
      assert {:ok, %{definition: definition}} = Persistence.fetch_revision(@identity)

      bounds = tier_bounds(definition)

      assert map_size(bounds) == 3

      for {tier, {lower, upper}} <- bounds do
        assert is_number(lower) and is_number(upper), "the #{tier} bound must be finite"
        assert lower < upper, "the #{tier} bound must be a non-empty range"
      end
    end

    test "does not depend on the study seed or the declared family alpha", %{
      document_opts: opts
    } do
      assert {:ok, _revision} = Study.create_revision(valid_yaml(opts))
      assert {:ok, %{definition: default}} = Persistence.fetch_revision(@identity)

      other_yaml =
        opts
        |> valid_yaml()
        |> String.replace("id: example-study", "id: other-study")
        |> String.replace("seed: 31415", "seed: 7")
        |> String.replace("alpha: 0.05", "alpha: 0.1")

      assert {:ok, _revision} =
               Study.create_revision(other_yaml)

      assert {:ok, %{definition: other}} =
               Persistence.fetch_revision(%Revision{study_id: "other-study", revision: 1})

      assert tier_bounds(other) == tier_bounds(default)
    end
  end

  describe "INPUT-03 frozen revision identity" do
    test "reloads the same derived views from the stored definition", %{document_opts: opts} do
      yaml = valid_yaml(opts)

      assert {:ok, _revision} = Study.create_revision(yaml)
      assert {:ok, parsed} = Definition.parse(valid_attrs(opts))
      assert {:ok, %{definition: stored}} = Persistence.fetch_revision(@identity)

      assert stored.seed == parsed.seed
      assert stored.family == parsed.family
      assert stored.provenance == parsed.provenance
      assert Definition.comparisons(stored) == Definition.comparisons(parsed)
      assert Definition.collection_groups(stored) == Definition.collection_groups(parsed)
      assert Definition.pilot_capacity(stored) == Definition.pilot_capacity(parsed)
    end

    test "rejects a different definition under the frozen identity and keeps the original", %{
      document_opts: opts
    } do
      assert {:ok, _revision} = Study.create_revision(valid_yaml(opts))

      changed = String.replace(valid_yaml(opts), "alpha: 0.05", "alpha: 0.1")
      assert {:error, %Error{category: :conflict}} = Study.create_revision(changed)

      assert {:ok, %{definition: stored}} = Persistence.fetch_revision(@identity)
      assert %{family: %{alpha: 0.05}} = stored
    end
  end

  defp with_model_weights(opts, weights, transform \\ &Function.identity/1) do
    alias NetworkDefense.Graph.{Graph, Graphs}
    alias NetworkDefense.Nodes.{Host, MissionCapability}

    graph =
      EnterpriseTopology.generate(
        title: "weighted model",
        hosts: 8,
        seed: 5
      )

    capabilities = graph |> Graph.nodes() |> Enum.filter(&(&1.type == MissionCapability))
    assert Enum.count(capabilities) == 2

    graph =
      if weights == [] do
        Enum.reduce(capabilities, graph, fn node, g -> Graph.remove_node_by_id(g, node.id) end)
      else
        Enum.zip(capabilities, weights)
        |> Enum.reduce(graph, fn {node, weight}, g ->
          Graph.update_node(g, %{node | data: %{node.data | impact_weight: weight}})
        end)
      end

    {:ok, stored} = Graphs.insert(transform.(graph))
    foothold = Enum.find(Graph.nodes(stored), &(&1.type == Host)).id

    opts
    |> Keyword.update!(:tier_graphs, &Map.put(&1, :small, stored.revision_id))
    |> Keyword.update!(:tier_footholds, &Map.put(&1, :small, foothold))
  end

  defp tier_bounds(definition) do
    Map.new(definition.tiers, fn tier ->
      {tier_name(tier), tier |> model_bound() |> bound_range()}
    end)
  end
end
