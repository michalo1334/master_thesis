defmodule NetworkDefense.Evaluation.Final.Actions.CorrectFinalFamily do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Family.Client
  alias NetworkDefense.Evaluation.Family.Contracts.{HolmRequest, RawResult}
  alias NetworkDefense.Evaluation.Final.Binding
  alias NetworkDefense.Evaluation.Final.Collector

  alias NetworkDefense.Evaluation.Final.Contracts.{
    FinalError,
    Request,
    Result,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Final.{TaskFailure, Wire}

  # Final fan-in task.
  #
  # It verifies the complete declared family, applies one Holm correction to
  # all raw p-values in declared order, and stores one typed Final result. A
  # failure stores no result. A retry repeats only this pure correction call.
  #
  # The fan-in repeats the snapshot metadata, byte count, declared order,
  # resource caps, and source Pilot binding before the correction call. A
  # snapshot or Pilot that changed after the members ran therefore stops the
  # run with no Holm dispatch.

  @impl true
  def execute(_args, %{run_id: run_id}) do
    with {:ok, request, payload} <- load(run_id),
         {:ok, members} <- Collector.collect(run_id, request, payload),
         {:ok, correction} <- correction_request(request, members),
         {:ok, response} <- call_correction(correction),
         {:ok, result} <- Result.from_response(request, members, response) do
      Wire.result(result)
    else
      {:error, :permanent, error} -> TaskFailure.raise_permanent(error)
      {:error, :temporary, error} -> TaskFailure.raise_retryable(error)
      {:error, %FinalError{} = error} -> TaskFailure.raise_permanent(error)
    end
  end

  defp load(run_id) do
    with {:ok, %Request{} = request} <-
           run_id |> Gust.Flows.get_run!() |> Map.fetch!(:params) |> Request.parse(),
         {:ok, %SnapshotPayload{} = payload} <- Binding.verify(request) do
      {:ok, request, payload}
    end
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

      {:error, classification, error} ->
        {:error, classification, correction_error(classification, error)}
    end
  end

  defp correction_error(_classification, %{issues: [_ | _]} = error),
    do: FinalError.from_foreign(error)

  defp correction_error(_classification, %{schema_errors: [_ | _]} = error),
    do: FinalError.from_foreign(error)

  defp correction_error(:temporary, _error), do: FinalError.unavailable()
  defp correction_error(:permanent, _error), do: FinalError.invalid_correction()
end
