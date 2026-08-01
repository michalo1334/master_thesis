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
  alias NetworkDefense.Simulation.Run

  # Ecto may add binds beyond the values present in each input map.
  @max_bind_parameters 45_000
  @iteration_batch_size 500

  def insert(%Experiment{runs: runs} = experiment) when is_list(runs) do
    runtime_ms = experiment.runtime_ms
    experiment = %{experiment | runtime_ms: 0}

    with {:ok, experiment} <- create(experiment),
         {:ok, experiment} <- append_batch(experiment, runs, runtime_ms) do
      complete(experiment)
    end
  end

  def create(%Experiment{} = experiment) do
    experiment
    |> Map.put(:runs, [])
    |> then(&Experiment.changeset(&1, experiment_attrs(experiment)))
    |> Repo.insert(timeout: :infinity)
  end

  def append_batch(%Experiment{} = experiment, runs, runtime_ms) when is_list(runs) do
    Repo.transaction(
      fn ->
        experiment = lock!(experiment.id)

        if experiment.status != "running" do
          Repo.rollback(:not_running)
        end

        if experiment.completed_trials + length(runs) > experiment.total_trials do
          Repo.rollback(:too_many_trials)
        end

        now = DateTime.truncate(DateTime.utc_now(), :second)

        run_maps =
          Enum.map(runs, fn run ->
            run
            |> db_map(Run, %{
              experiment_id: experiment.id,
              inserted_at: now,
              updated_at: now
            })
          end)

        run_count = insert_all(Run, run_maps, :run)
        if run_count != length(runs), do: Repo.rollback(:run)

        insert_iteration_steps(runs, now)

        experiment
        |> Experiment.changeset(%{
          completed_trials: experiment.completed_trials + length(runs),
          runtime_ms: experiment.runtime_ms + runtime_ms
        })
        |> update_or_rollback(:experiment)
      end,
      timeout: :infinity
    )
  end

  def complete(%Experiment{} = experiment) do
    Repo.transaction(
      fn ->
        experiment = lock!(experiment.id)

        if experiment.completed_trials != experiment.total_trials do
          Repo.rollback(:incomplete)
        end

        experiment
        |> Experiment.changeset(%{status: "completed"})
        |> update_or_rollback(:experiment)
      end,
      timeout: :infinity
    )
  end

  def fail(experiment_id) do
    Repo.get(Experiment, experiment_id)
    |> case do
      %Experiment{status: "running"} = experiment ->
        experiment
        |> Experiment.changeset(%{status: "failed"})
        |> Repo.update(timeout: :infinity)

      _ ->
        :ok
    end
  end

  def resume(experiment_id) do
    Repo.transaction(
      fn ->
        experiment = lock!(experiment_id)

        cond do
          is_nil(experiment) ->
            Repo.rollback(:not_found)

          is_nil(experiment.initial_foothold_node_id) ->
            Repo.rollback(:not_resumable)

          experiment.status == "completed" ->
            Repo.rollback(:completed)

          experiment.completed_trials == experiment.total_trials ->
            Repo.rollback(:completed)

          true ->
            experiment
            |> Experiment.changeset(%{status: "running"})
            |> update_or_rollback(:experiment)
        end
      end,
      timeout: :infinity
    )
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
      case Repo.insert_all(schema.__schema__(:source), chunk,
             on_conflict: :nothing,
             timeout: :infinity
           ) do
        {count, nil} when count == length(chunk) -> inserted_count + count
        _ -> Repo.rollback(operation)
      end
    end)
  end

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
      :initial_foothold_node_id
    ])
  end

  defp lock!(id) do
    from(experiment in Experiment, where: experiment.id == ^id, lock: "FOR UPDATE")
    |> Repo.one()
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
