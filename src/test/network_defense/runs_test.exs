defmodule NetworkDefense.RunsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Evaluation.EvaluationManifest
  alias NetworkDefense.Evaluation.EvaluationRun
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Runs
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiments

  describe "active/0" do
    test "lists running runs of every kind, newest first" do
      graph = insert_graph("runs-active")
      graph_revision_id = graph.revision_id

      experiment = insert_experiment(graph_revision_id, "running")
      optimization = insert_optimization(graph_revision_id, "running")
      evaluation = insert_evaluation("running")

      runs = Runs.active()

      assert MapSet.new(Enum.map(runs, & &1.kind)) ==
               MapSet.new(["simulation", "optimization", "evaluation"])

      assert runs == Enum.sort_by(runs, & &1.started_at, {:desc, DateTime})

      assert %{
               id: ^experiment,
               kind: "simulation",
               title: "runs-active",
               status: "running",
               completed: 0,
               total: 10,
               started_at: %DateTime{}
             } = Enum.find(runs, &(&1.id == experiment))

      assert %{
               id: ^optimization,
               kind: "optimization",
               title: "runs-active",
               status: "running",
               completed: nil,
               total: nil,
               started_at: %DateTime{}
             } = Enum.find(runs, &(&1.id == optimization))

      assert %{
               id: ^evaluation,
               kind: "evaluation",
               title: "evaluation-title",
               status: "running",
               completed: nil,
               total: nil,
               started_at: %DateTime{}
             } = Enum.find(runs, &(&1.id == evaluation))
    end

    test "omits completed and failed runs" do
      graph = insert_graph("runs-inactive")
      graph_revision_id = graph.revision_id

      insert_experiment(graph_revision_id, "completed")
      insert_experiment(graph_revision_id, "failed")
      insert_optimization(graph_revision_id, "completed")
      insert_optimization(graph_revision_id, "failed")
      insert_evaluation("completed")
      insert_evaluation("failed")

      assert Runs.active() == []
    end
  end

  defp insert_graph(title) do
    assert {:ok, graph} = Graphs.insert(GraphFixtures.persisted_credential_graph(title))
    graph
  end

  defp insert_experiment(graph_revision_id, status) do
    experiment =
      Experiment.new(
        graph_revision_id: graph_revision_id,
        master_seed: 1,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 10,
        completed_trials: 0,
        status: status
      )

    assert {:ok, experiment} = Experiments.create(experiment)
    experiment.id
  end

  defp insert_optimization(graph_revision_id, status) do
    attrs = %{
      graph_revision_id: graph_revision_id,
      strategy: "cvss",
      requested_budget: 1,
      status: status
    }

    attrs =
      if status == "completed" do
        Map.put(attrs, :output_graph_revision_id, graph_revision_id)
      else
        attrs
      end

    %OptimizationRun{}
    |> OptimizationRun.changeset(attrs)
    |> Repo.insert!()
    |> Map.fetch!(:id)
  end

  defp insert_evaluation(status) do
    manifest =
      %EvaluationManifest{}
      |> EvaluationManifest.changeset(%{
        manifest_id: "manifest-#{System.unique_integer([:positive])}",
        title: "evaluation-title",
        content: %{}
      })
      |> Repo.insert!()

    graph = insert_graph("evaluation-graph")

    %EvaluationRun{}
    |> EvaluationRun.changeset(%{
      evaluation_manifest_id: manifest.id,
      source_graph_revision_id: graph.revision_id,
      resolved_manifest: %{},
      status: status
    })
    |> Repo.insert!()
    |> Map.fetch!(:id)
  end
end
