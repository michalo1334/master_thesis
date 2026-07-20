defmodule NetworkDefense.Simulation.Reports do
  @moduledoc """
  Context module for loading simulation data for report computation.
  """

  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.MultiState
  alias NetworkDefense.Simulation.State

  import Ecto.Query

  @doc """
  Fully loads a MultiState with graph and all nested simulation data
  needed to compute a report.
  """
  def load_for_report(multi_state_id) do
    MultiState
    |> Repo.get(multi_state_id)
    |> case do
      nil -> nil
      multi_state -> multi_state |> Repo.preload(:graph) |> load_simulations()
    end
  end

  defp load_simulations(multi_state) do
    simulations =
      State
      |> where([s], s.multi_state_id == ^multi_state.id)
      |> order_by([s], asc: :inserted_at)
      |> Repo.all()
      |> Repo.preload(:iterations)
      |> Enum.map(fn sim ->
        %{sim | iterations: Enum.sort_by(sim.iterations, & &1.index, :desc)}
      end)

    %{multi_state | simulations: simulations}
  end
end
