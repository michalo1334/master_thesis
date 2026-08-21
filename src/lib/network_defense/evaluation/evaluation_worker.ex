defmodule NetworkDefense.Evaluation.EvaluationWorker do
  @moduledoc false

  use Oban.Worker, queue: :evaluations, max_attempts: 1

  alias NetworkDefense.Evaluation

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}}) do
    case Evaluation.run(run_id) do
      {:ok, _run} -> :ok
      {:error, _reason} -> {:error, :failed}
    end
  end
end
