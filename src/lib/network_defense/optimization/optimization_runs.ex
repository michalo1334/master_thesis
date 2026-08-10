defmodule NetworkDefense.Optimization.OptimizationRuns do
  @moduledoc """
  Persists `OptimizationRun` records and their applied `OptimizationAction` rows.
  """

  import Ecto.Query

  alias NetworkDefense.Optimization.OptimizationAction
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Repo

  def create(%OptimizationRun{} = run) do
    run
    |> OptimizationRun.changeset(%{
      graph_revision_id: run.graph_revision_id,
      strategy: run.strategy,
      objective: run.objective,
      requested_budget: run.requested_budget,
      used_budget: run.used_budget,
      runtime_ms: run.runtime_ms,
      status: run.status,
      seed: run.seed,
      simulation_config: run.simulation_config
    })
    |> Repo.insert()
  end

  def complete(%OptimizationRun{} = run, attrs) do
    Repo.transaction(fn -> complete_locked(lock!(run.id), attrs) end)
  end

  defp complete_locked(%OptimizationRun{status: "running"} = run, attrs) do
    with {:ok, run} <- complete_run(run, attrs),
         {:ok, _actions} <- insert_actions(run.id, Map.fetch!(attrs, :actions)) do
      run
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp complete_locked(nil, _attrs), do: Repo.rollback(:not_found)
  defp complete_locked(_run, _attrs), do: Repo.rollback(:not_running)

  def fail(run_id) do
    Repo.get(OptimizationRun, run_id)
    |> case do
      %OptimizationRun{status: "running"} = run ->
        run
        |> OptimizationRun.changeset(%{status: "failed"})
        |> Repo.update()

      _ ->
        :ok
    end
  end

  def list_by_graph_revisions(graph_revision_ids) when is_list(graph_revision_ids) do
    OptimizationRun
    |> where([run], run.graph_revision_id in ^graph_revision_ids)
    |> where([run], run.status == "completed")
    |> order_by([run], desc: run.inserted_at)
    |> preload(:graph_revision)
    |> Repo.all()
  end

  def list_by_graph_revision(graph_revision_id),
    do: list_by_graph_revisions([graph_revision_id])

  def load(id) do
    case Repo.get(OptimizationRun, id) do
      nil -> nil
      run -> Repo.preload(run, actions: actions_query())
    end
  end

  defp complete_run(%OptimizationRun{} = run, attrs) do
    attrs = Map.take(attrs, [:used_budget, :runtime_ms, :output_graph_revision_id])

    run
    |> OptimizationRun.changeset(Map.put(attrs, :status, "completed"))
    |> Repo.update()
  end

  defp insert_actions(run_id, actions) do
    actions
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {action, position}, {:ok, acc} ->
      case insert_action(run_id, position, action) do
        {:ok, saved} -> {:cont, {:ok, [saved | acc]}}
        {:error, _changeset} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, actions} -> {:ok, Enum.reverse(actions)}
      {:error, _changeset} = error -> error
    end
  end

  defp insert_action(run_id, position, action) do
    %OptimizationAction{optimization_run_id: run_id, position: position}
    |> OptimizationAction.changeset(action)
    |> Repo.insert()
  end

  defp actions_query do
    from action in OptimizationAction, order_by: [asc: action.position]
  end

  defp lock!(id) do
    from(run in OptimizationRun, where: run.id == ^id, lock: "FOR UPDATE")
    |> Repo.one()
  end
end
