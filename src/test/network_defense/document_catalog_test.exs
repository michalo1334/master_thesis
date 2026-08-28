defmodule NetworkDefense.DocumentCatalogTest do
  use NetworkDefense.DataCase

  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Evaluation.{EvaluationManifest, EvaluationRun}
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.{Experiment, Experiments}
  alias NetworkDefense.DocumentCatalog
  alias NetworkDefenseWeb.Contracts.Dashboard.Workspace.FetchDocumentCatalogPayload

  test "paginates catalog items after applying all filters" do
    baseline_count = DocumentCatalog.document_catalog(filters()).total_count
    alpha_title = "alpha %_\\ graph"

    assert {:ok, alpha} = Graphs.insert(Graph.new(alpha_title))
    assert {:ok, _beta} = Graphs.insert(Graph.new("beta graph"))
    assert {:ok, output} = Graphs.append_optimization(alpha)
    assert {:ok, experiment} = create_experiment(alpha)
    assert {:ok, optimization} = create_optimization(alpha, output.revision_id)

    catalog = DocumentCatalog.document_catalog(filters())

    assert catalog.total_count == baseline_count + 5

    assert %{output_revision_kind: nil, output_revision_number: nil} =
             Enum.find(catalog.items, &(&1.id == alpha.revision_id))

    assert %{output_revision_kind: nil, output_revision_number: nil} =
             Enum.find(catalog.items, &(&1.id == experiment.id))

    assert %{
             output_graph_revision_id: output_revision_id,
             output_revision_kind: "optimization",
             output_revision_number: 2
           } = Enum.find(catalog.items, &(&1.id == optimization.id))

    assert output_revision_id == output.revision_id

    assert %{
             types: types,
             graphs: graphs,
             strategies: strategies,
             revision_kinds: revision_kinds
           } = catalog.filter_options

    assert "graph" in types
    assert "optimization_report" in types
    assert "simulation_report" in types
    assert Map.fetch!(Map.new(graphs, &{&1.id, &1.title}), alpha.id) == alpha_title

    assert "cvss" in strategies
    assert "initial" in revision_kinds

    assert %{total_count: 4} = DocumentCatalog.document_catalog(filters(%{"search" => "alpha"}))
    assert %{total_count: 4} = DocumentCatalog.document_catalog(filters(%{"search" => "%_"}))
    assert %{total_count: 4} = DocumentCatalog.document_catalog(filters(%{"search" => "\\"}))

    assert %{items: [%{kind: "simulation_report"}]} =
             DocumentCatalog.document_catalog(
               filters(%{"search" => "Simulation report", "graph_ids" => [alpha.id]})
             )

    assert %{total_count: 3} =
             DocumentCatalog.document_catalog(
               filters(%{"search" => "initial #1", "graph_ids" => [alpha.id]})
             )

    assert %{total_count: 0} =
             DocumentCatalog.document_catalog(
               filters(%{"search" => "many", "graph_ids" => [alpha.id]})
             )

    assert %{items: [%{kind: "optimization_report"}]} =
             DocumentCatalog.document_catalog(
               filters(%{"search" => "cvss", "graph_ids" => [alpha.id]})
             )

    optimization = Enum.find(catalog.items, &(&1.kind == "optimization_report"))

    assert %{items: timestamp_items} =
             DocumentCatalog.document_catalog(
               filters(%{"search" => optimization.created_at, "graph_ids" => [alpha.id]})
             )

    assert Enum.any?(timestamp_items, &(&1.id == optimization.id))

    assert %{total_count: 1} =
             DocumentCatalog.document_catalog(
               filters(%{"types" => ["optimization_report"], "graph_ids" => [alpha.id]})
             )

    assert %{total_count: 4} =
             DocumentCatalog.document_catalog(filters(%{"graph_ids" => [alpha.id]}))

    assert %{total_count: 1} =
             DocumentCatalog.document_catalog(
               filters(%{"strategies" => ["cvss"], "graph_ids" => [alpha.id]})
             )

    assert %{total_count: 1} =
             DocumentCatalog.document_catalog(
               filters(%{"revision_kinds" => ["optimization"], "graph_ids" => [alpha.id]})
             )

    assert %{items: [_item], total_count: 4} =
             DocumentCatalog.document_catalog(
               filters(%{"graph_ids" => [alpha.id], "limit" => 1, "offset" => 1})
             )
  end

  test "scopes related items by graph without applying table filters or pagination" do
    assert {:ok, graph} = Graphs.insert(Graph.new("related graph"))
    assert {:ok, other} = Graphs.insert(Graph.new("other graph"))
    assert {:ok, child} = Graphs.append_optimization(graph)
    assert {:ok, experiment} = create_experiment(graph)
    assert {:ok, optimization} = create_optimization(graph, child.revision_id)
    assert {:ok, _other_experiment} = create_experiment(other)

    catalog =
      DocumentCatalog.document_catalog(
        filters(%{
          "related_graph_ids" => [graph.id],
          "search" => "never matches",
          "types" => ["graph"],
          "limit" => 1,
          "offset" => 0
        })
      )

    assert catalog.total_count == 0
    assert catalog.items == []

    assert Enum.map(catalog.related_items, & &1.id) ==
             [graph.revision_id, optimization.id, experiment.id, child.revision_id]

    assert Enum.all?(catalog.related_items, &(&1.graph_id == graph.id))

    assert Enum.find(catalog.related_items, &(&1.id == child.revision_id)).parent_revision_id ==
             graph.revision_id

    assert Enum.find(catalog.related_items, &(&1.id == experiment.id)).parent_revision_id == nil

    grouped =
      DocumentCatalog.document_catalog(
        filters(%{"related_graph_ids" => [graph.id], "limit" => 10})
      )

    assert Enum.map(grouped.items, & &1.id) ==
             [graph.revision_id, optimization.id, experiment.id, child.revision_id]
  end

  test "catalogs completed evaluation runs with manifest identity" do
    assert {:ok, graph} = Graphs.insert(Graph.new("analysis source"))

    assert {:ok, manifest} =
             %EvaluationManifest{}
             |> EvaluationManifest.changeset(%{
               manifest_id: "analysis-manifest",
               title: "Statistical analysis",
               content: %{}
             })
             |> Repo.insert()

    run_attrs = %{
      evaluation_manifest_id: manifest.id,
      source_graph_revision_id: graph.revision_id,
      resolved_manifest: %{},
      status: "completed"
    }

    assert {:ok, completed} =
             %EvaluationRun{}
             |> EvaluationRun.changeset(run_attrs)
             |> Repo.insert()

    completed_id = completed.id

    for status <- ["running", "failed"] do
      assert {:ok, _run} =
               %EvaluationRun{}
               |> EvaluationRun.changeset(%{run_attrs | status: status})
               |> Repo.insert()
    end

    assert %{total_count: 1, items: [item], filter_options: %{types: types}} =
             DocumentCatalog.document_catalog(
               filters(%{"types" => ["analysis_report"], "graph_ids" => [graph.id]})
             )

    assert "analysis_report" in types

    assert %{
             id: ^completed_id,
             kind: "analysis_report",
             manifest_id: "analysis-manifest",
             manifest_title: "Statistical analysis",
             graph_title: "analysis source"
           } = item

    assert %{items: [^item]} =
             DocumentCatalog.document_catalog(
               filters(%{"search" => "Statistical analysis", "graph_ids" => [graph.id]})
             )

    assert %{items: [^item]} =
             DocumentCatalog.document_catalog(
               filters(%{"search" => "Analysis report", "graph_ids" => [graph.id]})
             )
  end

  defp create_experiment(graph) do
    Experiment.new(%{
      graph_revision_id: graph.revision_id,
      master_seed: 1,
      iteration_count: 1,
      max_attempts: 1,
      total_trials: 1,
      completed_trials: 1,
      status: "completed"
    })
    |> Experiments.create()
  end

  defp create_optimization(graph, output_graph_revision_id) do
    %OptimizationRun{}
    |> OptimizationRun.changeset(%{
      graph_revision_id: graph.revision_id,
      output_graph_revision_id: output_graph_revision_id,
      strategy: "cvss",
      requested_budget: 1,
      status: "completed"
    })
    |> Repo.insert()
  end

  defp filters(attrs \\ %{}) do
    assert {:ok, filters} = FetchDocumentCatalogPayload.validate(attrs)
    filters
  end
end
