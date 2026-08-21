defmodule NetworkDefense.Simulations.SimulationWorker do
  @moduledoc false

  use Oban.Worker, queue: :simulations, max_attempts: 1

  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulations

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"experiment_id" => experiment_id, "correlation_id" => correlation_id}
      }) do
    case Simulations.run_or_resume(experiment_id, correlation_id) do
      {:ok, _experiment} ->
        :ok

      {:error, _reason} ->
        Experiments.fail(experiment_id)
        {:error, :failed}
    end
  end
end
