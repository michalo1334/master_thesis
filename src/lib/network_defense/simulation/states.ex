defmodule NetworkDefense.Simulation.States do
  @moduledoc """
  Persists `State` records into the `simulations` table.

  The struct represents run state; the table name reflects that
  each persisted row is a completed simulation run.
  """

  import Ecto.Query

  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.State

  def insert(%State{} = state) do
    Repo.transaction(fn ->
      simulation =
        %State{graph_id: graph_id(state)}
        |> State.changeset(state_attrs(state))
        |> insert_or_rollback(:simulation)

      iterations = Enum.map(state.iterations, &insert_iteration(&1, simulation.id))

      %{
        simulation
        | graph: state.graph,
          rules: state.rules,
          iterations: iterations
      }
    end)
  end

  def load(id) do
    case Repo.get(State, id) do
      nil -> nil
      simulation -> Repo.preload(simulation, iterations: iteration_query())
    end
  end

  defp insert_iteration(iteration, simulation_id) do
    %IterationStep{simulation_id: simulation_id}
    |> IterationStep.changeset(iteration_attrs(iteration))
    |> insert_or_rollback(:iteration_step)
  end

  defp insert_or_rollback(changeset, operation) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback({operation, changeset})
    end
  end

  defp graph_id(%State{graph_id: graph_id}) when is_binary(graph_id), do: graph_id
  defp graph_id(%State{graph: %{id: graph_id}}) when is_binary(graph_id), do: graph_id
  defp graph_id(_), do: nil

  defp state_attrs(state) do
    Map.take(state, [:initial_seed, :initial_attacker_state, :iteration_count])
  end

  defp iteration_attrs(iteration) do
    Map.take(iteration, [:index, :attempted_action, :success?, :attacker_state, :seed])
  end

  defp iteration_query do
    from(iteration in IterationStep, order_by: [desc: iteration.index])
  end
end
