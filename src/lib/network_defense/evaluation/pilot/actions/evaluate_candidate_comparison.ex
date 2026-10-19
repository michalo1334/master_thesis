defmodule NetworkDefense.Evaluation.Pilot.Actions.EvaluateCandidateComparison do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.EvidenceSnapshots

  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotError, PilotRequest}

  alias NetworkDefense.Evaluation.Pilot.{Client, TaskFailure, Work}

  # One mapped candidate comparison.
  #
  # The persisted item must equal the canonical item recomputed from the root
  # request and the snapshot. The action then loads exactly that comparison's
  # evidence, sends one bounded request, and stores compact row fields only.

  @impl true
  def execute(args, %{run_id: run_id}) do
    item = Keyword.fetch!(args, :item)

    with {:ok, request} <- load_request(run_id),
         {:ok, snapshot, payload} <- EvidenceSnapshots.load(request.snapshot_id),
         :ok <- PilotRequest.matches_snapshot(request, snapshot, payload),
         {:ok, items} <- Work.canonical_items(request, payload),
         {:ok, expected_item} <- locate(items, item, length(request.expected_comparisons)),
         {:ok, candidate_request} <- Work.candidate_request(request, payload, expected_item),
         {:ok, response} <- Client.compare(candidate_request) do
      Work.result_params(response)
    else
      {:error, :permanent, error} -> TaskFailure.raise_permanent(error)
      {:error, :temporary, error} -> TaskFailure.raise_retryable(error)
      {:error, %PilotError{} = error} -> TaskFailure.raise_permanent(error)
    end
  end

  defp load_request(run_id) do
    run_id
    |> Gust.Flows.get_run!()
    |> Map.fetch!(:params)
    |> PilotRequest.parse()
  end

  defp locate(items, item, comparison_count) do
    with {:ok, candidate_position} <- position(item["candidate_position"]),
         {:ok, comparison_position} <- position(item["comparison_position"]),
         index = candidate_position * comparison_count + comparison_position,
         %{} = expected <- Enum.at(items, index) do
      if expected == item do
        {:ok, expected}
      else
        {:error, PilotError.changed_candidate_result("A persisted pilot work item changed.")}
      end
    else
      nil -> {:error, PilotError.incomplete_pilot("A mapped work item has no canonical row.")}
      :error -> {:error, PilotError.incomplete_pilot("A mapped work item position is invalid.")}
      {:error, %PilotError{} = error} -> {:error, error}
    end
  end

  defp position(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp position(_value), do: :error
end
