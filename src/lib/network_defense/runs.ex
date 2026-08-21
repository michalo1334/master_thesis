defmodule NetworkDefense.Runs do
  @moduledoc """
  Lists active (status = "running") runs across simulation experiments,
  optimization runs, workflow runs, and evaluation runs, newest first.
  """

  import Ecto.Query

  alias NetworkDefense.Evaluation.EvaluationRun
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Workflows.WorkflowRun

  @spec active() :: [map()]
  def active do
    (active_experiments() ++
       active_optimizations() ++
       active_workflows() ++
       active_evaluations())
    |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
  end

  defp active_experiments do
    Experiment
    |> where([e], e.status == "running")
    |> preload(:graph_revision)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
    |> Enum.map(fn e ->
      %{
        id: e.id,
        kind: "simulation",
        title: e.graph_revision && e.graph_revision.title,
        status: e.status,
        completed: e.completed_trials,
        total: e.total_trials,
        started_at: e.inserted_at
      }
    end)
  end

  defp active_optimizations do
    OptimizationRun
    |> where([o], o.status == "running")
    |> preload(:graph_revision)
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
    |> Enum.map(fn o ->
      %{
        id: o.id,
        kind: "optimization",
        title: o.graph_revision && o.graph_revision.title,
        status: o.status,
        completed: nil,
        total: nil,
        started_at: o.inserted_at
      }
    end)
  end

  defp active_workflows do
    WorkflowRun
    |> where([w], w.status == "running")
    |> order_by([w], desc: w.inserted_at)
    |> Repo.all()
    |> Enum.map(fn w ->
      %{
        id: w.id,
        kind: "workflow",
        title: w.title,
        status: w.status,
        completed: nil,
        total: nil,
        started_at: w.inserted_at
      }
    end)
  end

  defp active_evaluations do
    EvaluationRun
    |> where([e], e.status == "running")
    |> preload(:evaluation_manifest)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
    |> Enum.map(fn e ->
      %{
        id: e.id,
        kind: "evaluation",
        title: e.evaluation_manifest && e.evaluation_manifest.title,
        status: e.status,
        completed: nil,
        total: nil,
        started_at: e.inserted_at
      }
    end)
  end
end
