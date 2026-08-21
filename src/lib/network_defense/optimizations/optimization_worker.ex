defmodule NetworkDefense.Optimizations.OptimizationWorker do
  @moduledoc false

  use Oban.Worker, queue: :optimizations, max_attempts: 1

  alias NetworkDefense.Optimization.Contracts.RunOptimizationRequest
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Optimizations

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id, "request" => request_params}}) do
    case RunOptimizationRequest.validate(request_params) do
      {:ok, request} ->
        case Optimizations.run_or_resume(run_id, request) do
          {:ok, _run} ->
            :ok

          {:error, _reason} ->
            OptimizationRuns.fail(run_id)
            {:error, :failed}
        end

      _ ->
        {:error, :invalid_request}
    end
  end
end
