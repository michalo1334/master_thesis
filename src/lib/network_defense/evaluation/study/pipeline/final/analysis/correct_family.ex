defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.CorrectFamily do
  @moduledoc false

  alias NetworkDefense.Evaluation.Family.Client
  alias NetworkDefense.Evaluation.Family.Contracts.{HolmRequest, RawResult}
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Collector
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Contracts.{Request, Result}
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Error, as: FinalError

  # Final fan-in step.
  #
  # It verifies the complete declared family, applies one Holm correction to
  # all raw p-values in declared order, and returns one typed Final result. A
  # failure stores no result. A retry repeats only this pure correction call.
  #
  # The fan-in repeats the snapshot metadata, byte count, declared order,
  # resource caps, and source Pilot binding before the correction call. A
  # snapshot or Pilot that changed after the members ran therefore stops the
  # run with no Holm dispatch.

  @spec run(IO.t()) ::
          {:ok, IO.t()}
          | {:error, FinalError.t()}
          | {:error, {:temporary, FinalError.t()}}
  def run(%IO{gust_run: %{id: run_id}} = io) do
    with {:ok, request, payload} <- IO.values(io),
         {:ok, members} <- Collector.collect(run_id, request, payload),
         {:ok, correction} <- correction_request(request, members),
         {:ok, response} <- call_correction(correction),
         {:ok, result} <- Result.from_response(request, members, response) do
      {:ok, %{io | result: result}}
    end
  end

  def run(%IO{}) do
    {:error, FinalError.incomplete_family("The persisted Final run is missing.")}
  end

  defp correction_request(%Request{} = request, members) do
    correction = %HolmRequest{
      schema_version: 1,
      family_id: request.family_id,
      method: request.method,
      alpha: request.analysis.alpha,
      expected_comparisons: request.expected_comparisons,
      raw_results: Enum.map(members, &raw_result/1)
    }

    correction
    |> HolmRequest.to_params()
    |> HolmRequest.parse()
  end

  defp raw_result(member) do
    %RawResult{
      identity: member.identity,
      raw_p_value: member.statistics.test["raw_p_value"] / 1
    }
  end

  # The correction client owns the retry classification: a transport failure
  # and a documented HTTP 500 or 503 reply are temporary. The owning Final error
  # must keep that classification, so only this pure correction call repeats. A
  # bounded Family error keeps its code, its rows, or its schema diagnostics
  # through the conversion, so a valid correction diagnostic is not hidden.
  defp call_correction(%HolmRequest{} = correction) do
    case Client.holm(correction) do
      {:ok, response} ->
        {:ok, response}

      {:error, :temporary, error} ->
        {:error, {:temporary, correction_error(:temporary, error)}}

      {:error, classification, error} ->
        {:error, correction_error(classification, error)}
    end
  end

  defp correction_error(_classification, %{issues: [_ | _]} = error),
    do: FinalError.from_foreign(error)

  defp correction_error(_classification, %{schema_errors: [_ | _]} = error),
    do: FinalError.from_foreign(error)

  defp correction_error(:temporary, _error), do: FinalError.unavailable()
  defp correction_error(:permanent, _error), do: FinalError.invalid_correction()

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.CorrectFamily,
      failures: NetworkDefense.Evaluation.Study.Pipeline.Final.TaskFailure

    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Contracts.Result
    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO
    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter

    @impl GustAdapter
    def decode(_args, %{run_id: run_id}), do: IO.load_from_gust_run(run_id)

    @impl GustAdapter
    def encode(%IO{result: %Result{} = result}), do: Result.to_params(result)
  end
end
