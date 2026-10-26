defmodule NetworkDefense.Optimizations.OptimizationWorker do
  @moduledoc false

  use Oban.Worker, queue: :optimizations, max_attempts: 1

  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Optimizations

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id, "correlation_id" => correlation_id}})
      when is_binary(run_id) and is_binary(correlation_id) do
    case Optimizations.run_reserved(run_id, correlation_id: correlation_id) do
      {:ok, _run} ->
        :ok

      {:error, _reason} ->
        OptimizationRuns.fail(run_id)
        {:error, :failed}
    end
  end

  def perform(%Oban.Job{}), do: {:error, :invalid_request}
end
