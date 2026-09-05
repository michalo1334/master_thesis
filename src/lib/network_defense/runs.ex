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

  def cancel(kind, id) when kind in ["simulation", "optimization", "evaluation"] do
    case kind do
      "simulation" ->
        cancel_record(Experiment, id, &NetworkDefense.Simulation.Experiments.cancel/1)

      "optimization" ->
        cancel_record(OptimizationRun, id, &NetworkDefense.Optimization.OptimizationRuns.cancel/1)

      "evaluation" ->
        NetworkDefense.Evaluation.cancel(id)
    end
  end

  def cancel(kind, id) when kind in [:simulation, :optimization, :evaluation],
    do: cancel(Atom.to_string(kind), id)

  def cancel(_kind, _id), do: {:error, :not_found}

  defp cancel_record(schema, id, cancel_fun) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      %{status: status} when status in [:running, "running"] -> cancel_fun.(id)
      _ -> {:error, :not_running}
    end
  end

  @spec active() :: [map()]
  def active do
    (active_experiments() ++
       active_optimizations() ++
       active_evaluations())
    |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
  end

  defp active_experiments do
    Experiment
    |> where([e], e.status == :running)
    |> preload(:graph_revision)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
    |> Enum.map(fn e ->
      %{
        id: e.id,
        kind: "simulation",
        title: e.graph_revision && e.graph_revision.title,
        status: Experiment.Status.to_wire(e.status),
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
