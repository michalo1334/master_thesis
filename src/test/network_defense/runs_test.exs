defmodule NetworkDefense.RunsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Optimization.{ExecutionConfig, OptimizationRun}
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Repo
  alias NetworkDefense.Rules.Registry, as: RulesRegistry
  alias NetworkDefense.Runs
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiments

  describe "active/0" do
    test "lists running simulations and optimizations, newest first" do
      graph = insert_graph("runs-active")
      experiment = insert_experiment(graph.revision_id, :running)
      optimization = insert_optimization(graph.revision_id, "running")

      runs = Runs.active()

      assert MapSet.new(Enum.map(runs, & &1.kind)) ==
               MapSet.new(["simulation", "optimization"])

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
    end

    test "omits completed and failed runs" do
      graph = insert_graph("runs-inactive")
      insert_experiment(graph.revision_id, :completed)
      insert_experiment(graph.revision_id, :failed)
      insert_optimization(graph.revision_id, "completed")
      insert_optimization(graph.revision_id, "failed")

      assert Runs.active() == []
    end

    test "cancels running runs and excludes them from active runs" do
      graph = insert_graph("runs-cancel")
      experiment = insert_experiment(graph.revision_id, :running)
      optimization = insert_optimization(graph.revision_id, "running")

      for {kind, id} <- [{:simulation, experiment}, {:optimization, optimization}] do
        assert {:ok, _} = Runs.cancel(kind, id)
        refute Enum.any?(Runs.active(), &(&1.id == id))
      end

      assert Repo.get!(Experiment, experiment).status == :cancelled
      assert Repo.get!(OptimizationRun, optimization).status == "cancelled"
    end

    test "cancelling terminal runs returns not_running" do
      graph = insert_graph("runs-terminal")
      experiment = insert_experiment(graph.revision_id, :completed)
      optimization = insert_optimization(graph.revision_id, "completed")

      for {kind, id, schema, status} <- [
            {:simulation, experiment, Experiment, :completed},
            {:optimization, optimization, OptimizationRun, "completed"}
          ] do
        assert Runs.cancel(kind, id) == {:error, :not_running}
        assert Repo.get!(schema, id).status == status
      end
    end

    test "cancelled runs cannot resume or complete" do
      graph = insert_graph("runs-no-resume")
      experiment = insert_experiment(graph.revision_id, :running)
      optimization = insert_optimization(graph.revision_id, "running")

      assert {:ok, _} = Runs.cancel(:simulation, experiment)
      assert {:ok, %{status: :cancelled}} = Experiments.start_empty(experiment)

      assert {:error, :not_running} =
               Experiments.complete_with_runs(Repo.get!(Experiment, experiment), [], 0)

      assert {:ok, _} = Runs.cancel(:optimization, optimization)
      assert {:ok, %{status: "cancelled"}} = OptimizationRuns.resume_or_load(optimization)

      assert {:error, :not_running} =
               OptimizationRuns.complete(Repo.get!(OptimizationRun, optimization), %{actions: []})
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
        rules: RulesRegistry.values(),
        require_pre_attack_feasibility: true,
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
      status: status,
      execution_config: %ExecutionConfig{
        candidate_action_types: [:patch_vulnerability],
        require_pre_attack_feasibility: true
      }
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
end
