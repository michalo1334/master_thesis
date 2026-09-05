defmodule NetworkDefense.Simulation.Experiments do
  @moduledoc """
  Persists `Experiment` records into the `experiments` table.

  An Experiment groups multiple simulation runs (each a `Run`) that share
  the same configuration but differ by derived seed.
  """

  import Ecto.Query

  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiment.Status
  alias NetworkDefense.Simulation.Run

  require Status

  # Ecto may add binds beyond the values present in each input map.
  @max_bind_parameters 45_000
  @iteration_batch_size 500

  def create(%Experiment{} = experiment) do
    experiment
    |> Map.put(:runs, [])
    |> then(&Experiment.changeset(&1, experiment_attrs(experiment)))
    |> Repo.insert(timeout: :infinity)
  end

  @spec start_empty(Ecto.UUID.t()) :: {:ok, Experiment.t()} | {:error, term()}
  def start_empty(experiment_id) do
    Repo.transaction(
      fn -> experiment_id |> lock!() |> start_empty_locked() end,
      timeout: :infinity
    )
  end

  @spec complete_with_runs(Experiment.t(), [Run.t()], non_neg_integer()) ::
          {:ok, Experiment.t()} | {:error, term()}
  def complete_with_runs(%Experiment{} = experiment, runs, runtime_ms) when is_list(runs) do
    run_count = length(runs)

    Repo.transaction(
      fn ->
        experiment.id |> lock!() |> complete_with_runs_locked(runs, run_count, runtime_ms)
      end,
      timeout: :infinity
    )
  end

  def fail(experiment_id) do
    Repo.update_all(
      from(e in Experiment, where: e.id == ^experiment_id and e.status == :running),
      set: [status: :failed, updated_at: DateTime.utc_now()]
    )

    :ok
  end

  def cancel(experiment_id) do
    result =
      Repo.update_all(
        from(e in Experiment, where: e.id == ^experiment_id and e.status == :running),
        set: [status: :cancelled, updated_at: DateTime.utc_now()]
      )

    Oban.cancel_all_jobs(
      from(j in Oban.Job,
        where: j.worker == ^"NetworkDefense.Simulations.SimulationWorker",
        where: fragment("? @> ?", j.args, ^%{"experiment_id" => experiment_id})
      )
    )

    case result do
      {1, _} -> {:ok, :cancelled}
      _ -> {:error, :not_running}
    end
  end

  def get(id), do: Repo.get(Experiment, id)

  defp db_map(%{} = struct, schema, additions) do
    map =
      struct |> Map.take(Map.keys(schema.__schema__(:dump))) |> Map.merge(additions)

    map = dump_embeds(map, schema)

    map =
      Map.new(map, fn {field, value} ->
        {schema.__schema__(:field_source, field), dump_uuid(field, value)}
      end)

    {key, _, _} = schema.__schema__(:autogenerate_id)
    if is_nil(map[key]), do: Map.delete(map, key), else: map
  end

  defp dump_embeds(map, Run) do
    Map.update!(map, :initial_attacker_state, &Ecto.embedded_dump(&1, :json))
  end

  defp dump_embeds(map, IterationStep) do
    map
    |> Map.update!(:attempted_action, &Ecto.embedded_dump(&1, :json))
    |> Map.update!(:attacker_state, &Ecto.embedded_dump(&1, :json))
  end

  defp dump_uuid(_field, nil), do: nil

  defp dump_uuid(field, value) when field in [:id, :graph_revision_id, :experiment_id, :run_id],
    do: Ecto.UUID.dump!(value)

  defp dump_uuid(_field, value), do: value

  def load(id) do
    case Repo.get(Experiment, id) do
      nil ->
        nil

      experiment ->
        Repo.preload(experiment, runs: runs_query())
    end
  end

  defp update_or_rollback(changeset, operation) do
    case Repo.update(changeset, timeout: :infinity) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback({operation, changeset})
    end
  end

  defp insert_all(_schema, [], _operation), do: 0

  defp insert_all(schema, rows, operation) do
    rows
    |> Enum.chunk_every(rows_per_insert(rows))
    |> Enum.reduce(0, fn chunk, inserted_count ->
      Repo.insert_all(schema.__schema__(:source), chunk,
        on_conflict: :nothing,
        timeout: :infinity
      )
      |> add_inserted_count(chunk, inserted_count, operation)
    end)
  end

  defp add_inserted_count({count, nil}, chunk, inserted_count, operation) do
    if count == Enum.count(chunk),
      do: inserted_count + count,
      else: Repo.rollback(operation)
  end

  defp add_inserted_count(_result, _chunk, _inserted_count, operation),
    do: Repo.rollback(operation)

  defp rows_per_insert([row | _rows]) do
    row
    |> map_size()
    |> then(&max(1, div(@max_bind_parameters, &1)))
  end

  defp insert_iteration_steps(runs, now) do
    runs
    |> Stream.flat_map(fn run -> Stream.map(run.iterations, &{run.id, &1}) end)
    |> Stream.map(fn {run_id, iteration} ->
      db_map(iteration, IterationStep, %{run_id: run_id, inserted_at: now, updated_at: now})
    end)
    |> Stream.chunk_every(@iteration_batch_size)
    |> Enum.reduce(0, fn batch, inserted_count ->
      inserted_count + insert_all(IterationStep, batch, :iteration_step)
    end)
  end

  defp experiment_attrs(experiment) do
    Map.take(experiment, [
      :master_seed,
      :iteration_count,
      :max_attempts,
      :runtime_ms,
      :total_trials,
      :completed_trials,
      :status,
      :initial_foothold_node_id,
      :evaluation_run_id,
      :optimization_run_id
    ])
  end

  defp lock!(id) do
    from(experiment in Experiment, where: experiment.id == ^id, lock: "FOR UPDATE")
    |> Repo.one()
  end

  defp start_empty_locked(nil), do: Repo.rollback(:not_found)

  defp start_empty_locked(%Experiment{status: status} = experiment)
       when Status.terminal?(status),
       do: experiment

  defp start_empty_locked(%Experiment{completed_trials: completed_trials})
       when completed_trials != 0,
       do: Repo.rollback(:partial_experiment_unsupported)

  defp start_empty_locked(%Experiment{status: status} = experiment)
       when Status.restartable?(status) do
    experiment
    |> Experiment.changeset(%{status: :running})
    |> update_or_rollback(:experiment)
  end

  defp start_empty_locked(%Experiment{status: :running} = experiment), do: experiment

  defp complete_with_runs_locked(nil, _runs, _run_count, _runtime_ms),
    do: Repo.rollback(:not_found)

  defp complete_with_runs_locked(%Experiment{status: status}, _runs, _run_count, _runtime_ms)
       when status != :running,
       do: Repo.rollback(:not_running)

  defp complete_with_runs_locked(
         %Experiment{completed_trials: completed_trials},
         _runs,
         _run_count,
         _runtime_ms
       )
       when completed_trials != 0,
       do: Repo.rollback(:incomplete)

  defp complete_with_runs_locked(
         %Experiment{total_trials: total_trials},
         _runs,
         run_count,
         _runtime_ms
       )
       when run_count != total_trials,
       do: Repo.rollback(:incomplete)

  defp complete_with_runs_locked(
         %Experiment{total_trials: run_count} = experiment,
         runs,
         run_count,
         runtime_ms
       ) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    run_maps =
      Enum.map(runs, fn run ->
        db_map(run, Run, %{experiment_id: experiment.id, inserted_at: now, updated_at: now})
      end)

    insert_all(Run, run_maps, :run)
    insert_iteration_steps(runs, now)

    experiment
    |> Experiment.changeset(%{
      completed_trials: experiment.total_trials,
      runtime_ms: runtime_ms,
      status: :completed
    })
    |> update_or_rollback(:experiment)
  end

  defp runs_query do
    from(run in Run,
      order_by: [asc: run.trial_index],
      preload: [iterations: ^iteration_order()]
    )
  end

  defp iteration_order do
    from(i in IterationStep, order_by: [desc: i.index])
  end
end
