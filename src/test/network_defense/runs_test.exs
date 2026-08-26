defmodule NetworkDefense.RunsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Evaluation.EvaluationManifest
  alias NetworkDefense.Evaluation.EvaluationRun
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Repo
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

    test "cancels running runs of every kind and excludes them from active runs" do
      graph = insert_graph("runs-cancel")
      experiment = insert_experiment(graph.revision_id, "running")
      optimization = insert_optimization(graph.revision_id, "running")
      evaluation = insert_evaluation("running")

      for {kind, id} <- [
            {:simulation, experiment},
            {:optimization, optimization},
            {:evaluation, evaluation}
          ] do
        assert {:ok, _} = Runs.cancel(kind, id)
        refute Enum.any?(Runs.active(), &(&1.id == id))
      end

      assert Repo.get!(Experiment, experiment).status == "cancelled"
      assert Repo.get!(OptimizationRun, optimization).status == "cancelled"
      assert Repo.get!(EvaluationRun, evaluation).status == "cancelled"
    end

    test "cancelling terminal runs returns not_running" do
      graph = insert_graph("runs-terminal")
      experiment = insert_experiment(graph.revision_id, "completed")
      optimization = insert_optimization(graph.revision_id, "completed")
      evaluation = insert_evaluation("failed")

      for {kind, id, schema, status} <- [
            {:simulation, experiment, Experiment, "completed"},
            {:optimization, optimization, OptimizationRun, "completed"},
            {:evaluation, evaluation, EvaluationRun, "failed"}
          ] do
        assert Runs.cancel(kind, id) == {:error, :not_running}
        assert Repo.get!(schema, id).status == status
      end
    end

    test "evaluation cancellation only cancels running children" do
      evaluation = insert_evaluation("running")
      graph = insert_graph("evaluation-children")
      completed_experiment = insert_experiment(graph.revision_id, "completed", evaluation)
      completed_optimization = insert_optimization(graph.revision_id, "completed", evaluation)
      running_optimization = insert_optimization(graph.revision_id, "running", evaluation)

      running_experiment =
        insert_experiment(graph.revision_id, "running", evaluation, running_optimization)

      assert {:ok, _} = Runs.cancel(:evaluation, evaluation)

      assert Repo.get!(Experiment, running_experiment).status == "cancelled"
      assert Repo.get!(Experiment, completed_experiment).status == "completed"
      assert Repo.get!(OptimizationRun, running_optimization).status == "cancelled"
      assert Repo.get!(OptimizationRun, completed_optimization).status == "completed"
    end

    test "cancelled runs cannot resume or complete" do
      graph = insert_graph("runs-no-resume")
      experiment = insert_experiment(graph.revision_id, "running")
      optimization = insert_optimization(graph.revision_id, "running")
      evaluation = insert_evaluation("running")

      assert {:ok, _} = Runs.cancel(:simulation, experiment)
      assert {:ok, %{status: "cancelled"}} = Experiments.resume_or_load(experiment)
      assert {:error, :not_running} = Experiments.complete(Repo.get!(Experiment, experiment))

      assert {:ok, _} = Runs.cancel(:optimization, optimization)
      assert {:ok, %{status: "cancelled"}} = OptimizationRuns.resume_or_load(optimization)

      assert {:error, :not_running} =
               OptimizationRuns.complete(Repo.get!(OptimizationRun, optimization), %{actions: []})

      assert {:ok, _} = Runs.cancel(:evaluation, evaluation)
      assert {:ok, %{status: "cancelled"}} = NetworkDefense.Evaluation.resume(evaluation)

      assert {:error, :not_running} =
               NetworkDefense.Evaluation.EvaluationRuns.complete(
                 Repo.get!(EvaluationRun, evaluation)
               )
    end
  end

  defp insert_graph(title) do
    assert {:ok, graph} = Graphs.insert(GraphFixtures.persisted_credential_graph(title))
    graph
  end

  defp insert_experiment(
         graph_revision_id,
         status,
         evaluation_run_id \\ nil,
         optimization_run_id \\ nil
       ) do
    experiment =
      Experiment.new(
        graph_revision_id: graph_revision_id,
        master_seed: 1,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 10,
        completed_trials: 0,
        status: status,
        evaluation_run_id: evaluation_run_id,
        optimization_run_id: optimization_run_id
      )

    assert {:ok, experiment} = Experiments.create(experiment)
    experiment.id
  end

  defp insert_optimization(graph_revision_id, status, evaluation_run_id \\ nil) do
    attrs = %{
      graph_revision_id: graph_revision_id,
      strategy: "cvss",
      requested_budget: 1,
      status: status,
      selection_seed: if(evaluation_run_id, do: System.unique_integer([:positive]), else: nil),
      model_variant: if(evaluation_run_id, do: :full, else: nil),
      evaluation_run_id: evaluation_run_id
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
