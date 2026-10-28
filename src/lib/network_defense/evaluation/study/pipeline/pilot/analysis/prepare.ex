defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Prepare do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.IO
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error, as: PilotError

  # Prepares the canonical candidate items from the loaded request.
  #
  # The public API already validated the request and the snapshot. The task
  # must not assume that persisted parameters are valid, so it recomputes the
  # work items before any mapped task exists.

  @spec run(IO.t()) :: {:ok, IO.t()} | {:error, PilotError.t()}
  def run(%IO{} = io) do
    case IO.candidates(io) do
      {:ok, candidates} -> {:ok, %{io | candidates: candidates}}
      {:error, %PilotError{} = error} -> {:error, error}
    end
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Prepare,
      failures: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.TaskFailure

    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter
    alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.IO

    @impl GustAdapter
    def decode(_args, %{run_id: run_id}), do: IO.load_from_gust_run(run_id)

    @impl GustAdapter
    def encode(%IO{candidates: candidates}) do
      %{"gust_task_items" => Enum.map(candidates, & &1.item)}
    end
  end
end
