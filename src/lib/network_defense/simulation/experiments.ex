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

  def insert(%Experiment{runs: runs} = experiment) when is_list(runs) do
    Repo.transaction(fn ->
      now = DateTime.truncate(DateTime.utc_now(), :second)

      experiment_record =
        experiment
        |> Map.put(:runs, [])
        |> then(&Experiment.changeset(&1, experiment_attrs(experiment)))
        |> insert_or_rollback(:experiment)

      run_maps =
        Enum.map(runs, fn run ->
          run
          |> db_map(Run, %{experiment_id: experiment_record.id, inserted_at: now, updated_at: now})
        end)

      run_count = insert_all(Run, run_maps, :run)
      if run_count != length(runs), do: Repo.rollback(:run)

      iteration_maps = iteration_step_maps(runs, now)

      insert_all(IterationStep, iteration_maps, :iteration_step)

      %{experiment_record | runs: []}
    end)
  end

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

  defp dump_uuid(field, value) when field in [:id, :graph_id, :experiment_id, :run_id],
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

  defp insert_or_rollback(changeset, operation) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback({operation, changeset})
    end
  end

  defp insert_all(_schema, [], _operation), do: 0

  defp insert_all(schema, rows, operation) do
    rows
    |> Enum.chunk_every(rows_per_insert(rows))
    |> Enum.reduce(0, fn chunk, inserted_count ->
      case Repo.insert_all(schema.__schema__(:source), chunk, on_conflict: :nothing) do
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

  defp iteration_step_maps(runs, now) do
    Enum.flat_map(runs, fn run ->
      Enum.map(run.iterations, fn iteration ->
        iteration
        |> db_map(IterationStep, %{run_id: run.id, inserted_at: now, updated_at: now})
      end)
    end)
  end

  defp experiment_attrs(experiment) do
    Map.take(experiment, [
      :master_seed,
      :iteration_count,
      :max_attempts,
      :lock_version,
      :runtime_ms
    ])
  end

  defp runs_query do
    from(run in Run,
      order_by: [asc: run.seed],
      preload: [iterations: ^iteration_order()]
    )
  end

  defp iteration_order do
    from(i in IterationStep, order_by: [desc: i.index])
  end
end
