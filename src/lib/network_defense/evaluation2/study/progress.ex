defmodule NetworkDefense.Evaluation2.Study.Progress do
  @moduledoc """
  Read-only canonical scope and durable counters for Study observation.

  Each item contributes once in its current replica. Durable completion proves
  optimization progress. Live simulation counters require the canonical Gust
  task and its current attempt. Read aggregation stays outside effect callbacks.
  """
  import Ecto.Query

  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.{CollectionItem, CollectionPlan, PhaseRun}
  alias NetworkDefense.Evaluation2.Study.Persistence.Executions
  alias NetworkDefense.Evaluation2.Study.ProgressSnapshot
  alias NetworkDefense.Evaluation2.Study.Tier
  alias NetworkDefense.Evaluation2.Study.Views
  alias NetworkDefense.Optimization.Persistence.OptimizationRun
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Persistence.Experiment

  def topic(execution_id), do: "study:execution:#{execution_id}"

  def notify(%PhaseRun{study_phase_id: phase_id}) do
    case Persistence.read(:progress, :phase, fn ->
           Repo.one(
             from p in Persistence.Phase, where: p.id == ^phase_id, select: p.study_execution_id
           )
         end) do
      {:ok, id} when is_binary(id) -> publish(id)
      _ -> :ok
    end
  end

  def notify(%{execution: %{id: id}}), do: publish(id)
  def notify(%{phase: %{study_execution_id: id}}), do: publish(id)
  def notify(_value), do: :ok

  defp publish(id) do
    Phoenix.PubSub.broadcast(NetworkDefense.PubSub, topic(id), {:study_changed, id})
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end

  @doc "Reconstruct public progress without accepting or dispatching work."
  def snapshot(execution_id, live \\ %{}) do
    with {:ok, context} <- Executions.fetch_context(execution_id),
         {:ok, snapshot} <-
           Persistence.read(:progress, :execution, fn -> build(context, live) end) do
      {:ok, snapshot}
    else
      {:error, %Persistence.Error{} = failure} -> {:error, Views.error(failure)}
    end
  end

  @doc "Return canonical Gust source identities for the server-side observer."
  def run_ids(execution_id) do
    with {:ok, uuid} <- Persistence.cast_id(execution_id, :progress, :execution) do
      Persistence.read(:progress, :execution, fn ->
        Repo.all(
          from r in PhaseRun,
            join: p in Persistence.Phase,
            on: p.id == r.study_phase_id,
            where: p.study_execution_id == ^uuid,
            select: r.gust_run_id
        )
      end)
    end
  end

  @doc "Return a bounded set of unfinished item identities in the current replica."
  def item_ids(execution_id) do
    with {:ok, context} <- Executions.fetch_context(execution_id) do
      Persistence.read(:progress, :execution, fn -> unfinished_items(context.active_phase) end)
    end
  end

  defp unfinished_items(active_phase) do
    with %{phase: phase} = stored <- active_phase,
         true <- phase in [:pilot_collection, :final_collection],
         %PhaseRun{} = run <- phase_runs(stored.id) |> current_run(),
         replica when is_integer(replica) <- replica(run.id) do
      Repo.all(
        from i in CollectionItem,
          left_join: e in Experiment,
          on: e.id == i.experiment_id,
          where:
            i.study_phase_run_id == ^run.id and i.replica_position == ^replica and
              (is_nil(e.status) or e.status != :completed),
          order_by: i.item_position,
          limit: 1_000,
          select: i.id
      )
    else
      _ -> []
    end
  end

  @doc "Decode an effect correlation into its item identity and stage."
  def correlation(payload) do
    with %{correlation_id: correlation} when is_binary(correlation) <- payload,
         [id, stage] when stage in ["optimization", "experiment"] <-
           String.split(correlation, "/"),
         {:ok, ^id} <- Ecto.UUID.cast(id) do
      {:ok, id, stage}
    else
      _ -> :ignore
    end
  end

  defp build(context, live) do
    status = Views.status(context.revision, context.execution)
    phase = context.active_phase || retained_phase(context.execution.id)

    base = %ProgressSnapshot{
      execution_id: status.execution_id,
      status: status,
      phase: phase && to_string(phase.phase)
    }

    if phase, do: phase_progress(base, phase, live), else: base
  end

  defp retained_phase(id) do
    Repo.one(
      from p in Persistence.Phase,
        where: p.study_execution_id == ^id,
        order_by: [desc: p.inserted_at, desc: p.id],
        limit: 1
    )
  end

  defp phase_progress(base, phase, live) do
    run = phase.id |> phase_runs() |> current_run()

    cond do
      is_nil(run) -> %{base | counters: waiting_counters(phase.phase)}
      phase.phase in [:pilot_analysis, :final_analysis] -> analysis_progress(base, run)
      true -> collection_progress(base, run, live)
    end
  end

  defp phase_runs(id), do: Repo.all(from r in PhaseRun, where: r.study_phase_id == ^id)
  defp current_run([]), do: nil

  defp current_run(runs) do
    order = [:single | Tier.all()] |> Enum.with_index() |> Map.new()
    ordered = Enum.sort_by(runs, &Map.fetch!(order, &1.run_key))
    ids = Enum.map(ordered, & &1.gust_run_id)

    statuses =
      Gust.Repo.all(from r in Gust.Flows.Run, where: r.id in ^ids, select: {r.id, r.status})
      |> Map.new()

    Enum.reduce_while(ordered, nil, fn run, _last_succeeded ->
      if Map.get(statuses, run.gust_run_id) == :succeeded,
        do: {:cont, run},
        else: {:halt, run}
    end)
  end

  defp replica(id),
    do:
      Repo.one(
        from i in CollectionItem,
          where: i.study_phase_run_id == ^id,
          select: max(i.replica_position)
      )

  defp collection_progress(base, run, live) do
    replica = replica(run.id)
    tier = if run.run_key == :single, do: nil, else: to_string(run.run_key)
    base = %{base | tier: tier, replica: replica, warm_up: replica == -1}

    if is_nil(replica) do
      %{base | counters: waiting_counters(:pilot_collection)}
    else
      query = item_effects(run.id, replica)

      {items, optimized, completed} =
        Repo.one(
          from [i, o, e] in query,
            select:
              {count(i.id), filter(count(i.id), o.status == "completed"),
               coalesce(sum(e.completed_trials), 0)}
        )

      total =
        Repo.one(
          from p in CollectionPlan,
            where: p.study_phase_run_id == ^run.id,
            select:
              fragment(
                "(SELECT COALESCE(SUM((item->>'attack_count')::bigint), 0)::bigint FROM jsonb_array_elements(?->'items') item)",
                p.items
              )
        ) || 0

      {partial, activity} = live_activity(run, replica, live)

      %{
        base
        | activity: activity,
          counters: [
            counter(optimized, items, "optimization_items"),
            counter(min(completed + partial, total), total, "simulation_trials")
          ]
      }
    end
  end

  defp item_effects(run_id, replica) do
    from i in CollectionItem,
      left_join: o in OptimizationRun,
      on: o.id == i.optimization_run_id,
      left_join: e in Experiment,
      on: e.id == i.experiment_id,
      where: i.study_phase_run_id == ^run_id and i.replica_position == ^replica
  end

  defp live_activity(run, replica, live) do
    task_ids =
      live
      |> Map.values()
      |> Enum.map(&Map.get(&1, :observation_task_id))
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    tasks =
      Gust.Repo.all(
        from t in Gust.Flows.Task,
          where: t.run_id == ^run.gust_run_id and t.id in ^task_ids,
          select: %{
            id: t.id,
            name: t.name,
            attempt: t.attempt,
            status: t.status,
            params: t.params
          }
      )
      |> Map.new(&{&1.id, &1})

    ids = live |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    effects =
      Repo.all(
        from [i, _o, e] in item_effects(run.id, replica),
          where: i.id in ^ids,
          select:
            {i.id, %{status: e.status, completed: e.completed_trials, total: e.total_trials}}
      )
      |> Map.new()

    Enum.reduce(live, {0, retry_activity(run.gust_run_id)}, fn {{id, stage}, payload},
                                                               {partial, detail} ->
      task = Map.get(tasks, Map.get(payload, :observation_task_id))
      effect = Map.get(effects, id)

      if current_event?(task, id, stage, payload) and not is_nil(effect) do
        amount = partial_trials(stage, effect, payload)

        detail = detail || bounded_detail(payload, stage)
        {partial + amount, detail}
      else
        {partial, detail}
      end
    end)
  end

  defp partial_trials("experiment", %{status: :running} = effect, payload) do
    min(max(Map.get(payload, :completed, 0) - (effect.completed || 0), 0), effect.total || 0)
  end

  defp partial_trials(_stage, _effect, _payload), do: 0

  defp current_event?(%{status: :running} = task, id, stage, payload) do
    expected = if stage == "optimization", do: "optimization", else: "simulation"

    task.attempt == Map.get(payload, :observation_attempt) and
      task.params["collection_item_id"] == id and String.contains?(task.name, expected)
  end

  defp current_event?(_task, _id, _stage, _payload), do: false

  defp bounded_detail(payload, stage) do
    case Map.get(payload, :detail) do
      detail when is_binary(detail) ->
        String.slice(detail, 0, 200)

      _ ->
        if(stage == "experiment",
          do: "Running simulation trials",
          else: "Selecting a defense plan"
        )
    end
  end

  defp retry_activity(run_id) do
    count =
      Gust.Repo.one(
        from t in Gust.Flows.Task,
          where: t.run_id == ^run_id and t.status == :retrying,
          select: count(t.id)
      )

    if count > 0, do: "Retrying #{count} work items", else: nil
  end

  defp analysis_progress(base, run) do
    counts =
      Gust.Repo.all(
        from t in Gust.Flows.Task,
          where: t.run_id == ^run.gust_run_id,
          group_by: t.status,
          select: {t.status, count(t.id)}
      )

    total = counts |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    completed =
      counts |> Enum.filter(&(elem(&1, 0) == :succeeded)) |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    %{
      base
      | activity: retry_activity(run.gust_run_id),
        counters: [counter(completed, if(total == 0, do: nil, else: total), "analysis_jobs")]
    }
  end

  defp waiting_counters(phase) when phase in [:pilot_analysis, :final_analysis],
    do: [counter(0, nil, "analysis_jobs")]

  defp waiting_counters(_phase),
    do: [counter(0, nil, "optimization_items"), counter(0, nil, "simulation_trials")]

  defp counter(completed, total, unit), do: %{completed: completed, total: total, unit: unit}
end
