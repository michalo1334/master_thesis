defmodule NetworkDefense.Evaluation.Pilot.Actions.Prepare do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.EvidenceSnapshots

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    PilotError,
    PilotRequest
  }

  alias NetworkDefense.Evaluation.Pilot.{TaskFailure, Work}

  # Repeats pilot validation from persisted run parameters.
  #
  # The public API already validated the request and the snapshot. The task
  # must not assume that persisted parameters are valid, so it reloads the
  # snapshot, checks the declared comparison order, and builds the canonical
  # work items before any mapped task exists.

  @impl true
  def execute(_args, %{run_id: run_id}) do
    with {:ok, request} <- load_request(run_id),
         {:ok, snapshot, payload} <- EvidenceSnapshots.load(request.snapshot_id),
         :ok <- PilotRequest.matches_snapshot(request, snapshot, payload),
         :ok <- Work.preflight(request, payload),
         {:ok, items} <- Work.canonical_items(request, payload) do
      %{"gust_task_items" => items}
    else
      {:error, %PilotError{} = error} -> TaskFailure.raise_permanent(error)
    end
  end

  defp load_request(run_id) do
    run_id
    |> Gust.Flows.get_run!()
    |> Map.fetch!(:params)
    |> PilotRequest.parse()
  end
end
