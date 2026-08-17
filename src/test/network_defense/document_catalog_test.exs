defmodule NetworkDefense.DocumentCatalogTest do
  use NetworkDefense.DataCase

  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.{Optimizations, Simulations}
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.{Experiment, Experiments}
  alias NetworkDefense.Workflows
  alias NetworkDefense.DocumentCatalog
  alias NetworkDefenseWeb.Web.Contracts.FetchDocumentCatalogPayload

  test "paginates catalog items after applying all filters and exposes analysis lineage" do
    baseline_count = DocumentCatalog.document_catalog(filters()).total_count
    alpha_title = "alpha %_\\ graph"

    assert {:ok, alpha} = Graphs.insert(Graph.new(alpha_title))
    assert {:ok, _beta} = Graphs.insert(Graph.new("beta graph"))
    assert {:ok, producer} = Workflows.start("two_step", %{})
    assert {:ok, input} = Workflows.start("two_step", %{"graph_revision_id" => alpha.revision_id})
    assert {:ok, output} = Graphs.append_optimization(alpha)
    assert {:ok, experiment} = create_experiment(alpha, producer.id)
    assert {:ok, optimization} = create_optimization(alpha, output.revision_id, producer.id)

    catalog = DocumentCatalog.document_catalog(filters())

    assert catalog.total_count == baseline_count + 5

    assert %{analyses: [%{id: input_id, title: input_title}]} =
             Enum.find(catalog.items, &(&1.id == alpha.revision_id))

    assert input_id == input.id
    assert input_title == input.title

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

    assert catalog.items
           |> Enum.filter(&(&1.graph_id == alpha.id))
           |> Enum.all?(fn item ->
             item.analyses
             |> Enum.map(& &1.id)
             |> MapSet.new()
             |> MapSet.subset?(MapSet.new([producer.id, input.id]))
           end)

    assert %{
             types: types,
             graphs: graphs,
             analyses: analyses,
             strategies: strategies,
             revision_kinds: revision_kinds
           } = catalog.filter_options

    assert "graph" in types
    assert "optimization_report" in types
    assert "simulation_report" in types
    assert Map.fetch!(Map.new(graphs, &{&1.id, &1.title}), alpha.id) == alpha_title

    assert %{producer.id => producer.title, input.id => input.title} ==
             Map.new(analyses, &{&1.id, &1.title})

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

    assert %{total_count: 1} =
             DocumentCatalog.document_catalog(
               filters(%{"search" => input.id, "graph_ids" => [alpha.id]})
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
             DocumentCatalog.document_catalog(filters(%{"analysis_ids" => [input.id]}))

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

  test "replaces graph analysis grouping without changing workflow assignment" do
    assert {:ok, graph} = Graphs.insert(Graph.new("grouped graph"))
    assert {:ok, first} = Workflows.start("two_step", %{})
    assert {:ok, second} = Workflows.start("two_step", %{})

    assert {:ok, analyses} =
             Workflows.replace_graph_analyses(graph.revision_id, [second.id, first.id])

    assert MapSet.new(Enum.map(analyses, & &1.id)) == MapSet.new([first.id, second.id])

    assert %{analysisIds: analysis_ids} =
             Enum.find(Graphs.list_summaries(), &(&1.revisionId == graph.revision_id))

    assert MapSet.new(analysis_ids) == MapSet.new([first.id, second.id])

    assert %{analyses: catalog_analyses} =
             DocumentCatalog.document_catalog(filters())
             |> then(fn catalog -> Enum.find(catalog.items, &(&1.id == graph.revision_id)) end)

    assert MapSet.new(Enum.map(catalog_analyses, & &1.id)) == MapSet.new([first.id, second.id])
    assert {:ok, []} = Workflows.replace_graph_analyses(graph.revision_id, [])
  end

  test "changes a completed report analysis or clears it" do
    assert {:ok, graph} = Graphs.insert(Graph.new("report graph"))
    assert {:ok, analysis} = Workflows.start("two_step", %{})
    assert {:ok, output} = Graphs.append_optimization(graph)
    assert {:ok, experiment} = create_experiment(graph, nil)
    assert {:ok, optimization} = create_optimization(graph, output.revision_id, nil)

    assert {:ok, experiment} = Simulations.set_analysis(experiment.id, analysis.id)
    assert experiment.analysis_id == analysis.id
    assert {:ok, experiment} = Simulations.set_analysis(experiment.id, nil)
    assert is_nil(experiment.analysis_id)

    assert {:ok, optimization} = Optimizations.set_analysis(optimization.id, analysis.id)
    assert optimization.analysis_id == analysis.id
    assert {:ok, optimization} = Optimizations.set_analysis(optimization.id, nil)
    assert is_nil(optimization.analysis_id)
  end

  defp create_experiment(graph, analysis_id) do
    Experiment.new(%{
      graph_revision_id: graph.revision_id,
      analysis_id: analysis_id,
      master_seed: 1,
      iteration_count: 1,
      max_attempts: 1,
      total_trials: 1,
      completed_trials: 1,
      status: "completed"
    })
    |> Experiments.create()
  end

  defp create_optimization(graph, output_graph_revision_id, analysis_id) do
    %OptimizationRun{}
    |> OptimizationRun.changeset(%{
      graph_revision_id: graph.revision_id,
      analysis_id: analysis_id,
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
