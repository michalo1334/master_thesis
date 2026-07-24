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

      {run_count, nil} = Repo.insert_all(Run, run_maps, on_conflict: :nothing)
      if run_count != length(runs), do: Repo.rollback(:run)

      iteration_maps = iteration_step_maps(runs, now)

      iteration_maps
      |> Enum.chunk_every(10_000)
      |> Enum.each(&insert_iteration_chunk/1)

      %{experiment_record | runs: []}
    end)
  end

  defp db_map(%{} = struct, schema, additions) do
    map =
      struct |> Map.take(Map.keys(schema.__schema__(:dump))) |> Map.merge(additions)

    case schema.__schema__(:autogenerate_id) do
      {key, _, _} -> if is_nil(map[key]), do: Map.delete(map, key), else: map
      nil -> map
    end
  end

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

  defp insert_iteration_chunk(chunk) do
    case Repo.insert_all(IterationStep, chunk, on_conflict: :nothing) do
      {count, nil} when count == length(chunk) -> :ok
      _ -> Repo.rollback(:iteration_step)
    end
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
      :seed,
      :iteration_count,
      :run_count,
      :initial_attacker_state,
      :lock_version,
      :runtime_ms
    ])
  end

  defp runs_query do
    from(run in Run,
      order_by: [asc: run.initial_seed],
      preload: [iterations: ^iteration_order()]
    )
  end

  defp iteration_order do
    from(i in IterationStep, order_by: [desc: i.index])
  end
end
