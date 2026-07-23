defmodule NetworkDefense.Simulation.Reports do
  @moduledoc """
  Context module for loading simulation data for report computation.
  """

  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Run

  import Ecto.Query

  @doc """
  Fully loads an Experiment with graph and all nested run data
  needed to compute a report.
  """
  def load_for_report(experiment_id) do
    Experiment
    |> Repo.get(experiment_id)
    |> case do
      nil -> nil
      experiment -> experiment |> Repo.preload(:graph) |> load_runs()
    end
  end

  defp load_runs(experiment) do
    runs =
      Run
      |> where([run], run.experiment_id == ^experiment.id)
      |> order_by([run], asc: :inserted_at)
      |> Repo.all()
      |> Repo.preload(:iterations)
      |> Enum.map(fn run ->
        %{run | iterations: Enum.sort_by(run.iterations, & &1.index, :desc)}
      end)

    %{experiment | runs: runs}
  end
end
