defmodule NetworkDefense.Simulation.Runs do
  @moduledoc """
  Persists `Run` records into the `simulation_runs` table.
  """

  import Ecto.Query

  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.Run

  def insert(%Run{} = run) do
    Repo.transaction(fn ->
      persisted_run =
        %Run{graph_id: graph_id(run)}
        |> Run.changeset(run_attrs(run))
        |> insert_or_rollback(:run)

      iterations = Enum.map(run.iterations, &insert_iteration(&1, persisted_run.id))

      %{
        persisted_run
        | graph: run.graph,
          rules: run.rules,
          iterations: iterations
      }
    end)
  end

  def load(id) do
    case Repo.get(Run, id) do
      nil -> nil
      run -> Repo.preload(run, iterations: iteration_query())
    end
  end

  defp insert_iteration(iteration, run_id) do
    %IterationStep{run_id: run_id}
    |> IterationStep.changeset(iteration_attrs(iteration))
    |> insert_or_rollback(:iteration_step)
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

  defp run_attrs(run) do
    Map.take(run, [:initial_seed, :initial_attacker_state, :iteration_count])
  end

  defp iteration_attrs(iteration) do
    Map.take(iteration, [:index, :attempted_action, :success?, :attacker_state, :seed])
  end

  defp iteration_query do
    from(iteration in IterationStep, order_by: [desc: iteration.index])
  end
end
