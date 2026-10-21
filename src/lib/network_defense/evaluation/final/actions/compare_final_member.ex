defmodule NetworkDefense.Evaluation.Final.Actions.CompareFinalMember do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Comparison.Actions.Compare
  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Final.Binding
  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request}
  alias NetworkDefense.Evaluation.Final.{Member, TaskFailure}

  # Final-member adapter.
  #
  # The mapped item carries one declared position and one declared identity.
  # The adapter rebuilds the accepted comparison request from the stored Final
  # snapshot and the submitted seed, then delegates the statistics to the
  # accepted Stage 2 action. It only adds the declared identity and checks the
  # returned statistics against the same request.
  #
  # Before any statistics call the adapter repeats the snapshot metadata, the
  # snapshot byte count, the declared order, the resource caps, and the actual
  # source Pilot binding. A snapshot or Pilot that changed after preparation
  # therefore stops the member with no compute call.

  @impl true
  def execute(args, %{run_id: run_id} = context) do
    item = Keyword.fetch!(args, :item)

    with {:ok, request} <- load_request(run_id),
         {:ok, %{position: position, identity: identity}} <- Member.parse_item(item),
         {:ok, payload} <- Binding.verify(request),
         {:ok, comparison_request} <- Member.comparison_request(request, payload, position),
         :ok <- check_declared(request, position, identity) do
      statistics =
        Compare.execute([request: ComparisonRequest.to_params(comparison_request)], context)

      case Member.parse_result(
             %{"identity" => Identity.to_params(identity), "statistics" => statistics},
             comparison_request
           ) do
        {:ok, _member} ->
          %{"identity" => Identity.to_params(identity), "statistics" => statistics}

        {:error, %FinalError{} = error} ->
          TaskFailure.raise_permanent(error)
      end
    else
      {:error, %FinalError{} = error} -> TaskFailure.raise_permanent(error)
    end
  end

  defp load_request(run_id) do
    run_id
    |> Gust.Flows.get_run!()
    |> Map.fetch!(:params)
    |> Request.parse()
  end

  defp check_declared(%Request{} = request, position, identity) do
    if Identity.matches?(Enum.at(request.expected_comparisons, position), identity) do
      :ok
    else
      {:error,
       FinalError.changed_member("A mapped Final member does not hold its declared identity.")}
    end
  end
end
