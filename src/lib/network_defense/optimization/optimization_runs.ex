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
      evaluation_run_id: run.evaluation_run_id,
      model_variant: run.model_variant,
      strategy: run.strategy,
      requested_budget: run.requested_budget,
      used_budget: run.used_budget,
      runtime_ms: run.runtime_ms,
      status: run.status,
      seed: run.seed,
      selection_seed: run.selection_seed,
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
    case Repo.transaction(fn -> fail_locked(lock!(run_id)) end) do
      {:ok, %OptimizationRun{} = run} -> {:ok, run}
      {:ok, :ok} -> :ok
    end
  end

  defp fail_locked(%OptimizationRun{status: "running"} = run) do
    run
    |> OptimizationRun.changeset(%{status: "failed"})
    |> Repo.update!()
  end

  defp fail_locked(_run), do: :ok

  def cancel(run_id) do
    result =
      Repo.update_all(
        from(r in OptimizationRun, where: r.id == ^run_id and r.status == "running"),
        set: [status: "cancelled", updated_at: DateTime.utc_now()]
      )

    Oban.cancel_all_jobs(
      from(j in Oban.Job,
        where: j.worker == ^"NetworkDefense.Optimizations.OptimizationWorker",
        where: fragment("? @> ?", j.args, ^%{"run_id" => run_id})
      )
    )

    case result do
      {1, _} -> {:ok, :cancelled}
      _ -> {:error, :not_running}
    end
  end

  def cancel_by_evaluation(evaluation_run_id) do
    OptimizationRun
    |> where([r], r.evaluation_run_id == ^evaluation_run_id and r.status == "running")
    |> Repo.update_all(set: [status: "cancelled", updated_at: DateTime.utc_now()])
  end

  def resume_or_load(run_id) do
    Repo.transaction(fn ->
      case lock!(run_id) do
        nil ->
          Repo.rollback(:not_found)

        %OptimizationRun{status: status} = run when status in ["completed", "cancelled"] ->
          run

        %OptimizationRun{} = run ->
          run
          |> OptimizationRun.changeset(%{status: "running"})
          |> Repo.update!()
      end
    end)
  end

  def list_by_graph_revisions(graph_revision_ids) when is_list(graph_revision_ids) do
    OptimizationRun
    |> where([run], run.graph_revision_id in ^graph_revision_ids)
    |> where([run], run.status == "completed")
    |> order_by([run], desc: run.inserted_at)
    |> preload(:graph_revision)
    |> Repo.all()
  end

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
