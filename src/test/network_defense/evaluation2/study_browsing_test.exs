defmodule NetworkDefense.Evaluation2.StudyBrowsingTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.{Definition, Persistence, Revision}
  alias NetworkDefense.Evaluation2Test.{FoundationFixtures, GraphFixtures}
  alias NetworkDefenseWeb.StudyWire

  setup do
    tiers = GraphFixtures.insert_tiers()
    attrs = FoundationFixtures.valid_attrs(GraphFixtures.document_opts(tiers))
    %{attrs: attrs}
  end

  test "structured and YAML construction share immutable resolved definitions and exact seeds", %{
    attrs: attrs
  } do
    seed = 9_007_199_254_740_993
    attrs = Map.put(attrs, "seed", seed)
    assert {:ok, parsed} = Definition.parse(attrs)
    assert {:ok, resolved} = Definition.resolve(parsed)
    assert {:ok, stored} = Persistence.insert_revision(resolved)
    params = Map.put(attrs, "seed", Integer.to_string(seed))
    assert params["seed"] == Integer.to_string(seed)
    assert {:ok, revision} = Study.create_revision_from_params(params)
    assert {:ok, ^revision} = Study.create_revision(Jason.encode!(attrs))
    assert {:ok, ^stored} = Persistence.fetch_revision(revision)
    assert {:ok, detail} = Study.get_revision(revision)
    assert detail.authored.seed == Integer.to_string(seed)
    assert detail.structure.comparisons == length(Definition.comparisons(resolved))

    assert {:ok, ^revision} =
             Study.create_revision_from_params(
               StudyWire.definition_params(StudyWire.wire(detail.authored))
             )

    assert {:error, %{category: :conflict}} =
             Study.create_revision_from_params(Map.put(params, "seed", "1"))
  end

  test "structured errors keep seed issue paths and reject foreign Host membership", %{
    attrs: attrs
  } do
    assert {:error, %{issues: [%{code: "invalid_seed", path: ["seed"]}]}} =
             Study.create_revision_from_params(Map.put(attrs, "seed", "1.5"))

    attrs =
      put_in(
        attrs,
        ["tiers", "small", "foothold_node_id"],
        attrs["tiers"]["medium"]["foothold_node_id"]
      )

    assert {:error, %{category: :validation_failed}} = Study.create_revision_from_params(attrs)
  end

  test "bounded revision pages keep literal search and stable identity order", %{attrs: attrs} do
    for {name, revision} <- [{"literal_%", 1}, {"literal_%", 2}, {"literal-ab", 1}] do
      attrs = put_in(attrs, ["study"], %{"id" => name, "revision" => revision})
      assert {:ok, _} = Study.create_revision_from_params(attrs)
    end

    assert {:ok, first} = Study.list_revisions(%{search: "literal_%", page_size: 1})
    assert first.total == 2
    assert [%{revision: %{revision: 2}, execution_count: 0, latest_state: nil}] = first.entries
    assert {:ok, second} = Study.list_revisions(%{search: "literal_%", page_size: 1, page: 2})
    assert [%{revision: %{revision: 1}}] = second.entries
    assert {:error, _} = Study.list_revisions(%{page_size: 101})
    assert {:error, _} = Study.list_revisions(%{page: 0})
    assert {:error, _} = Study.list_revisions(%{page_size: 0})
    assert {:error, _} = Study.list_revisions(%{search: :invalid})
    assert {:error, _} = Study.list_revisions(%{search: String.duplicate("x", 201)})
    assert {:ok, %{total: 3}} = Study.list_revisions(%{search: "  "})
    assert {:error, %{issues: [%{code: "invalid_page_request"}]}} = Study.list_revisions(page: 1)

    assert {:error, %{issues: [%{code: "invalid_page_request"}]}} =
             Study.list_revisions(%{"page" => 1})
  end

  test "missing revision differs from empty execution history and lists stay isolated", %{
    attrs: attrs
  } do
    assert {:ok, revision} = Study.create_revision_from_params(attrs)
    assert {:ok, %{entries: [], total: 0}} = Study.list_executions(revision, %{})

    assert {:error, %{issues: [%{code: "revision_not_found"}]}} =
             Study.list_executions(%Revision{study_id: "missing", revision: 1}, %{})

    assert {:ok, context} = Persistence.Executions.start_execution(revision)
    other = put_in(attrs, ["study", "revision"], 2)
    assert {:ok, other_revision} = Study.create_revision_from_params(other)
    assert {:ok, _} = Persistence.Executions.start_execution(other_revision)
    assert {:ok, %{entries: [entry], total: 1}} = Study.list_executions(revision, %{})
    assert entry.execution_id == context.execution.id
    refute Map.has_key?(Map.from_struct(entry), :gust_run_id)
    assert {:ok, progress} = Study.progress(entry.execution_id)
    assert progress.status.state == :collecting_pilot
    assert Enum.all?(progress.counters, &is_nil(&1.total))

    assert {:error, %{issues: [%{code: "result_not_available"}]}} =
             Study.result(entry.execution_id)
  end

  test "authoring options expose registered actions and alternatives" do
    assert {:ok, options} = Study.definition_options()
    assert "patch_vulnerability" in options.actions
    refute Enum.any?(options.alternatives, &(&1.value == "cvss"))
    assert Enum.any?(options.alternatives, & &1.scoring_required)
  end
end
