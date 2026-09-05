defmodule NetworkDefense.Simulations.SimulationWorker do
  @moduledoc false

  use Oban.Worker, queue: :simulations, max_attempts: 1

  alias NetworkDefense.Simulations

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"experiment_id" => experiment_id, "correlation_id" => correlation_id}
      }) do
    case Simulations.run(experiment_id, correlation_id: correlation_id, publish_events: true) do
      {:ok, _experiment} ->
        :ok

      {:error, _reason} ->
        {:error, :failed}
    end
  end
end
