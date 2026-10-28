defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.EvaluateCandidate do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Client
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.IO.CandidateItem
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Work
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error, as: PilotError

  # One mapped candidate comparison.
  #
  # The candidate item is already the canonical row recomputed from the declared
  # request and the snapshot. The action loads exactly that comparison's
  # evidence, sends one bounded request, and keeps compact row fields only.

  @spec run(CandidateItem.t()) ::
          {:ok, CandidateItem.t()}
          | {:error, PilotError.t()}
          | {:error, :temporary, PilotError.t()}
  def run(%CandidateItem{item: item} = candidate) when is_map(item) do
    with {:ok, request, payload} <- CandidateItem.values(candidate),
         {:ok, candidate_request} <- Work.candidate_request(request, payload, item),
         {:ok, result} <- Client.compare(candidate_request) do
      {:ok, %{candidate | result: result}}
    end
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.EvaluateCandidate,
      failures: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.TaskFailure

    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter
    alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.IO
    alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.IO.CandidateItem
    alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Work

    @impl GustAdapter
    def decode(args, %{run_id: run_id}) do
      with {:ok, io} <- IO.load_from_gust_run(run_id) do
        IO.candidate(io, Keyword.fetch!(args, :item))
      end
    end

    @impl GustAdapter
    def encode(%CandidateItem{result: result}) when not is_nil(result) do
      Work.result_params(result)
    end
  end
end
