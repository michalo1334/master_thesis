defmodule NetworkDefense.Evaluations do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
  alias NetworkDefense.Evaluation.Comparison.{Wire, Workflow}
  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Family
  alias NetworkDefense.Evaluation.Family.Contracts.FamilyRequest
  alias NetworkDefense.Evaluation.Pilot
  alias NetworkDefense.Evaluation.Pilot.Contracts.{EvidenceSnapshotInput, PilotRequest}

  def submit_comparison(attrs) do
    with {:ok, request} <- ComparisonRequest.parse(attrs) do
      request
      |> Wire.request()
      |> Workflow.submit()
    end
  end

  def await_comparison(run_id, timeout_ms), do: Workflow.await(run_id, timeout_ms)
  def get_comparison_result(run_id), do: Workflow.result(run_id)

  def submit_family(attrs) do
    with {:ok, request} <- FamilyRequest.parse(attrs) do
      request
      |> Family.Wire.request()
      |> Family.Workflow.submit()
    end
  end

  def await_family(run_id, timeout_ms), do: Family.Workflow.await(run_id, timeout_ms)
  def get_family_result(run_id), do: Family.Workflow.result(run_id)

  def create_evidence_snapshot(attrs) do
    with {:ok, input} <- EvidenceSnapshotInput.parse(attrs), do: EvidenceSnapshots.create(input)
  end

  def get_evidence_snapshot(snapshot_id), do: EvidenceSnapshots.get(snapshot_id)

  def submit_pilot(attrs) do
    with {:ok, request} <- PilotRequest.parse(attrs),
         {:ok, snapshot, payload} <- EvidenceSnapshots.load(request.snapshot_id),
         :ok <- PilotRequest.matches_snapshot(request, snapshot, payload),
         :ok <- Pilot.Work.preflight(request, payload) do
      request
      |> Pilot.Wire.request()
      |> Pilot.Workflow.submit()
    end
  end

  def await_pilot(run_id, timeout_ms), do: Pilot.Workflow.await(run_id, timeout_ms)
  def get_pilot_result(run_id), do: Pilot.Workflow.result(run_id)
end
