defmodule NetworkDefense.Evaluation.Family.Actions.CorrectFamily do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Family.{Client, Collector, Wire}

  alias NetworkDefense.Evaluation.Family.Contracts.{
    FamilyRequest,
    FamilyResult,
    HolmRequest,
    RawResult
  }

  alias NetworkDefense.Evaluation.Family.TaskFailure

  # Fan-in task.
  #
  # It verifies the complete persisted family, applies one Holm correction to
  # all raw p-values, and stores one typed family result. A failure stores no
  # family result. A retry repeats only this pure correction call.

  @impl true
  def execute(_args, %{run_id: run_id}) do
    with {:ok, request} <- load_request(run_id),
         {:ok, members} <- Collector.collect(run_id, request),
         {:ok, correction} <- correction_request(request, members),
         {:ok, response} <- Client.holm(correction),
         {:ok, result} <- FamilyResult.from_response(request, members, response) do
      Wire.result(result)
    else
      {:error, :permanent, error} -> TaskFailure.raise_permanent(error)
      {:error, :temporary, error} -> TaskFailure.raise_retryable(error)
      {:error, error} -> TaskFailure.raise_permanent(error)
    end
  end

  defp load_request(run_id) do
    run_id
    |> Gust.Flows.get_run!()
    |> Map.fetch!(:params)
    |> FamilyRequest.parse()
  end

  defp correction_request(%FamilyRequest{} = request, members) do
    correction = %HolmRequest{
      schema_version: 1,
      family_id: request.family_id,
      method: request.method,
      alpha: request.alpha,
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
end
