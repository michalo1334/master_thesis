defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Prepare do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Error, as: FinalError

  # Preparation repeats the strict Final contract and every cross-boundary
  # relation from persisted run parameters. The public API already validated the
  # request, but the task must not assume that persisted parameters are valid.
  #
  # The stored items are compact: a position and a declared identity. Evidence
  # matrices stay in PostgreSQL. Preparation runs before any mapped comparison
  # task exists, so a contract, snapshot, source-Pilot, resource, or count
  # violation stops the run with no member result.

  @spec run(IO.t()) :: {:ok, IO.t()} | {:error, FinalError.t()}
  def run(%IO{} = io) do
    case IO.comparisons(io) do
      {:ok, comparisons} -> {:ok, %{io | comparisons: comparisons}}
      {:error, %FinalError{} = error} -> {:error, error}
    end
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Prepare,
      failures: NetworkDefense.Evaluation.Study.Pipeline.Final.TaskFailure

    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO
    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter

    @impl GustAdapter
    def decode(_args, %{run_id: run_id}), do: IO.load_from_gust_run(run_id)

    @impl GustAdapter
    def encode(%IO{comparisons: comparisons}) do
      %{"gust_task_items" => Enum.map(comparisons, & &1.item)}
    end
  end
end
