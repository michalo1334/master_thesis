defmodule NetworkDefense.Simulation.MultiStates do
  @moduledoc """
  Persists `MultiState` records into the `multi_states` table.

  A MultiState groups multiple simulation runs (each a `State`) that share
  the same configuration but differ by derived seed.
  """

  import Ecto.Query

  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.MultiState
  alias NetworkDefense.Simulation.State

  def insert(%MultiState{simulations: simulations} = multi_state)
      when is_list(simulations) do
    Repo.transaction(fn ->
      multi_state_record =
        multi_state
        |> Map.put(:simulations, [])
        |> then(&MultiState.changeset(&1, multi_state_attrs(multi_state)))
        |> insert_or_rollback(:multi_state)

      child_states =
        Enum.map(simulations, fn state ->
          insert_state_with_iterations(state, multi_state_record.id)
        end)

      %{multi_state_record | simulations: child_states}
    end)
  end

  def load(id) do
    case Repo.get(MultiState, id) do
      nil ->
        nil

      multi_state ->
        Repo.preload(multi_state, simulations: simulations_query())
    end
  end

  defp insert_state_with_iterations(%State{iterations: iterations} = state, multi_state_id) do
    state_attrs =
      state
      |> Map.take([:initial_seed, :initial_attacker_state, :iteration_count])
      |> Map.put(:graph_id, graph_id(state))
      |> Map.put(:multi_state_id, multi_state_id)

    simulation =
      %State{}
      |> State.changeset(state_attrs)
      |> insert_or_rollback(:simulation)

    iteration_records =
      Enum.map(iterations, fn iteration ->
        %IterationStep{simulation_id: simulation.id}
        |> IterationStep.changeset(iteration_attrs(iteration))
        |> insert_or_rollback(:iteration_step)
      end)

    %{simulation | iterations: iteration_records}
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

  defp multi_state_attrs(multi_state) do
    Map.take(multi_state, [:seed, :iteration_count, :initial_attacker_state, :graph_id])
  end

  defp iteration_attrs(iteration) do
    Map.take(iteration, [:index, :attempted_action, :success?, :attacker_state, :seed])
  end

  defp simulations_query do
    from(s in State,
      order_by: [asc: s.initial_seed],
      preload: [iterations: ^iteration_order()]
    )
  end

  defp iteration_order do
    from(i in IterationStep, order_by: [desc: i.index])
  end
end
