defmodule NetworkDefense.Evaluation.EvaluationReport do
  @moduledoc """
  Projects one evaluation run into a dashboard report.

  The report contains the manifest and source graph identity, the run status,
  per-plan summaries, and aggregate experiment results. It never includes raw
  trial rows.
  """

  import Ecto.Query

  alias NetworkDefense.Evaluation.EvaluationRun
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.SimulationObjective
  alias NetworkDefense.ReportProgress
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Statistics

  @spec generate(EvaluationRun.t(), ReportProgress.progress_callback()) :: map() | nil
  def generate(%EvaluationRun{} = run, on_progress \\ ReportProgress.noop()) do
    case Graphs.load_revision(run.source_graph_revision_id) do
      %NetworkDefense.Graph.Graph{} = graph ->
        experiments = experiments(run.id)
        total = 2 + length(experiments)
        on_progress.(graph.id, graph.revision_id, 1, total, "Loading source graph")
        plans = plan_summaries(run.id)
        on_progress.(graph.id, graph.revision_id, 2, total, "Summarizing plans")

        %{
          run_id: run.id,
          status: run.status,
          failure_reason: run.failure_reason,
          manifest_id: run.evaluation_manifest.manifest_id,
          manifest_title: run.evaluation_manifest.title,
          graph_id: graph.id,
          source_graph_revision_id: run.source_graph_revision_id,
          source_graph_title: graph.title,
          plans: plans,
          experiments: experiment_summaries(experiments, graph, on_progress, total)
        }

      _ ->
        nil
    end
  end

  defp plan_summaries(evaluation_run_id) do
    OptimizationRun
    |> where([run], run.evaluation_run_id == ^evaluation_run_id)
    |> order_by([run], asc: run.strategy, asc: run.requested_budget, asc: run.selection_seed)
    |> preload(:actions)
    |> Repo.all()
    |> Enum.map(fn run ->
      %{
        id: run.id,
        strategy: run.strategy,
        requested_budget: run.requested_budget,
        selection_seed: run.selection_seed,
        used_budget: run.used_budget,
        action_count: length(run.actions),
        status: run.status
      }
    end)
  end

  defp experiments(evaluation_run_id) do
    Experiment
    |> where([experiment], experiment.evaluation_run_id == ^evaluation_run_id)
    |> order_by([experiment], asc: experiment.inserted_at, asc: experiment.id)
    |> preload(runs: :iterations)
    |> Repo.all()
  end

  defp experiment_summaries(experiments, graph, on_progress, total) do
    experiment_count = length(experiments)

    experiments
    |> Enum.sort_by(fn experiment ->
      {not is_nil(experiment.optimization_run_id), experiment.id}
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {experiment, index} ->
      on_progress.(
        graph.id,
        graph.revision_id,
        2 + index,
        total,
        "Aggregating experiment #{index} of #{experiment_count}"
      )

      counts = Enum.map(experiment.runs, &SimulationObjective.final_foothold_count/1)
      stats = Statistics.summary(counts)

      %{
        id: experiment.id,
        optimization_run_id: experiment.optimization_run_id,
        trial_count: length(experiment.runs),
        expected_blast_radius: stats.mean,
        median_blast_radius: stats.median,
        blast_radius_p95: stats.p95,
        blast_radius_p99: stats.p99,
        min_blast_radius: stats.min,
        max_blast_radius: stats.max
      }
    end)
  end
end
