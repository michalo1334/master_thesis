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
      experiment_record =
        experiment
        |> Map.put(:runs, [])
        |> then(&Experiment.changeset(&1, experiment_attrs(experiment)))
        |> insert_or_rollback(:experiment)

      persisted_runs =
        Enum.map(runs, fn run ->
          insert_run_with_iterations(run, experiment_record.id)
        end)

      %{experiment_record | runs: persisted_runs}
    end)
  end

  def load(id) do
    case Repo.get(Experiment, id) do
      nil ->
        nil

      experiment ->
        Repo.preload(experiment, runs: runs_query())
    end
  end

  defp insert_run_with_iterations(%Run{iterations: iterations} = run, experiment_id) do
    run_attrs =
      run
      |> Map.take([:initial_seed, :initial_attacker_state, :iteration_count])
      |> Map.put(:experiment_id, experiment_id)

    persisted_run =
      %Run{
        graph_id: graph_id(run),
        experiment_id: experiment_id
      }
      |> Run.changeset(run_attrs)
      |> insert_or_rollback(:run)

    iteration_records =
      Enum.map(iterations, fn iteration ->
        %IterationStep{run_id: persisted_run.id}
        |> IterationStep.changeset(iteration_attrs(iteration))
        |> insert_or_rollback(:iteration_step)
      end)

    %{persisted_run | iterations: iteration_records}
  end

  defp insert_or_rollback(changeset, operation) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback({operation, changeset})
    end
  end

  defp graph_id(%Run{graph_id: graph_id}) when is_binary(graph_id), do: graph_id
  defp graph_id(%Run{graph: %{id: graph_id}}) when is_binary(graph_id), do: graph_id
  defp graph_id(_), do: nil

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

  defp iteration_attrs(iteration) do
    Map.take(iteration, [:index, :attempted_action, :success?, :attacker_state, :seed])
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
