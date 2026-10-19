defmodule NetworkDefense.Evaluation.Pilot.PilotPersistenceTest do
  use NetworkDefense.DataCase, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox

  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Pilot.CanonicalJson
  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotError, PilotRequest, SnapshotPayload}
  alias NetworkDefense.Evaluation.Pilot.Limits
  alias NetworkDefense.Evaluation.PilotConformance
  alias NetworkDefense.Evaluations

  test "PERSIST-01: a snapshot is stored once and loads with its payload" do
    {:ok, snapshot} = Evaluations.create_evidence_snapshot(PilotConformance.snapshot())

    assert snapshot.phase == :pilot
    assert snapshot.schema_version == 1
    assert snapshot.family_id == "family-example"
    assert snapshot.payload_bytes > 0

    assert {:ok, loaded} = Evaluations.get_evidence_snapshot(snapshot.id)
    assert loaded.id == snapshot.id

    assert {:ok, ^loaded, payload} = EvidenceSnapshots.load(snapshot.id)
    assert Enum.count(payload.comparisons) == 2

    assert {:ok, bytes} = CanonicalJson.byte_size(SnapshotPayload.to_params(payload))
    assert bytes == loaded.payload_bytes
  end

  test "PERSIST-02: a stored payload with a changed byte count is rejected" do
    {:ok, snapshot} = Evaluations.create_evidence_snapshot(PilotConformance.snapshot())

    tampered =
      snapshot.payload
      |> put_in(["runtime_evidence", "plan_selection_ms"], [40.0, 40.0, 40.0])

    Repo.update_all(from(s in EvidenceSnapshot, where: s.id == ^snapshot.id),
      set: [payload: tampered]
    )

    assert {:error, %PilotError{issues: [issue]}} = EvidenceSnapshots.load(snapshot.id)
    assert issue["code"] == "changed_snapshot"
  end

  test "PERSIST-03: an unknown snapshot is reported as missing" do
    assert {:error, %PilotError{issues: [issue]}} =
             EvidenceSnapshots.load(Ecto.UUID.generate())

    assert issue["code"] == "snapshot_not_found"

    assert {:error, %PilotError{issues: [issue]}} = EvidenceSnapshots.load("not-a-uuid")
    assert issue["code"] == "snapshot_not_found"
  end

  test "PERSIST-04: the database may reserve a final row but no read path accepts it" do
    {:ok, snapshot} = Evaluations.create_evidence_snapshot(PilotConformance.snapshot())

    attrs = %{
      study_revision_id: snapshot.study_revision_id,
      phase: :final,
      schema_version: 1,
      family_id: snapshot.family_id,
      payload: snapshot.payload,
      payload_bytes: snapshot.payload_bytes
    }

    {:ok, final_snapshot} =
      Repo.insert(EvidenceSnapshot.create_changeset(%EvidenceSnapshot{}, attrs))

    assert {:error, %PilotError{issues: [issue]}} = EvidenceSnapshots.load(final_snapshot.id)
    assert issue["code"] == "snapshot_phase_mismatch"

    assert {:error, %PilotError{issues: [issue]}} =
             Evaluations.get_evidence_snapshot(final_snapshot.id)

    assert issue["code"] == "snapshot_phase_mismatch"

    request = PilotConformance.request_params(final_snapshot.id)

    assert {:error, %PilotError{issues: issues}} = Evaluations.submit_pilot(request)
    assert Enum.any?(issues, &(&1["code"] == "snapshot_phase_mismatch"))
  end

  test "PERSIST-04b: a Pilot row with a final evidence role is rejected on read" do
    {:ok, snapshot} = Evaluations.create_evidence_snapshot(PilotConformance.snapshot())
    final_payload = Map.put(snapshot.payload, "evidence_role", "final")
    {:ok, payload_bytes} = CanonicalJson.byte_size(final_payload)

    attrs = %{
      study_revision_id: snapshot.study_revision_id,
      phase: :pilot,
      schema_version: 1,
      family_id: snapshot.family_id,
      payload: final_payload,
      payload_bytes: payload_bytes
    }

    {:ok, final_role_snapshot} =
      Repo.insert(EvidenceSnapshot.create_changeset(%EvidenceSnapshot{}, attrs))

    assert {:error, %PilotError{}} = EvidenceSnapshots.load(final_role_snapshot.id)
    assert {:error, %PilotError{}} = Evaluations.get_evidence_snapshot(final_role_snapshot.id)
  end

  test "PERSIST-05: the public snapshot path rejects a final phase before any insert" do
    count = Repo.aggregate(EvidenceSnapshot, :count)
    attrs = Map.put(PilotConformance.snapshot(), "phase", "final")

    assert {:error, %PilotError{}} = Evaluations.create_evidence_snapshot(attrs)
    assert Repo.aggregate(EvidenceSnapshot, :count) == count
  end

  test "PERSIST-06: a snapshot that exceeds the configured payload limit is rejected whole" do
    original = Application.get_env(:network_defense, Limits)

    Application.put_env(
      :network_defense,
      Limits,
      Keyword.put(original, :snapshot_payload_bytes, 10)
    )

    on_exit(fn -> Application.put_env(:network_defense, Limits, original) end)

    count = Repo.aggregate(EvidenceSnapshot, :count)

    assert {:error, %PilotError{code: "request_too_large"}} =
             Evaluations.create_evidence_snapshot(PilotConformance.snapshot())

    assert Repo.aggregate(EvidenceSnapshot, :count) == count
  end

  test "PERSIST-08: an existing snapshot is rejected when a limit decreases" do
    {:ok, snapshot} = Evaluations.create_evidence_snapshot(PilotConformance.snapshot())
    original = Application.get_env(:network_defense, Limits)
    on_exit(fn -> Application.put_env(:network_defense, Limits, original) end)

    request = PilotConformance.request_params(snapshot.id)

    narrow =
      request
      |> put_in(["candidate_grid", "plan_count_candidates"], [5])
      |> put_in(["candidate_grid", "attacks_per_plan_candidates"], [10])

    cases = [
      {:snapshot_payload_bytes, 1, "request_too_large", request},
      {:snapshot_comparisons, 1, "validation_failed", request},
      {:plans_per_side, 5, "validation_failed", narrow},
      {:attack_columns, 10, "validation_failed", narrow}
    ]

    for {limit, value, expected_code, attrs} <- cases do
      Application.put_env(:network_defense, Limits, Keyword.put(original, limit, value))

      assert {:error, %PilotError{code: ^expected_code}} =
               Evaluations.get_evidence_snapshot(snapshot.id),
             "expected read to reject lowered limit #{inspect(limit)}"

      assert {:error, %PilotError{}} = Evaluations.submit_pilot(attrs),
             "expected submission to reject lowered limit #{inspect(limit)}"
    end
  end

  test "PERSIST-09: an over-limit alternative row count is rejected before insert" do
    with_limit(:plans_per_side, 5)
    count = Repo.aggregate(EvidenceSnapshot, :count)

    assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
             Evaluations.create_evidence_snapshot(snapshot_with_plan_rows(6, 5))

    assert has_limit_issue?(
             issues,
             ["payload", "comparisons", 0, "evidence", "alternative", "plans"],
             5,
             6
           )

    assert Repo.aggregate(EvidenceSnapshot, :count) == count
  end

  test "PERSIST-10: an over-limit reference row count is rejected before insert" do
    with_limit(:plans_per_side, 5)
    count = Repo.aggregate(EvidenceSnapshot, :count)

    assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
             Evaluations.create_evidence_snapshot(snapshot_with_plan_rows(5, 6))

    assert has_limit_issue?(
             issues,
             ["payload", "comparisons", 0, "evidence", "reference", "plans"],
             5,
             6
           )

    assert Repo.aggregate(EvidenceSnapshot, :count) == count
  end

  test "PERSIST-11: an over-limit attack column count is rejected before insert" do
    with_limit(:attack_columns, 11)
    count = Repo.aggregate(EvidenceSnapshot, :count)

    assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
             Evaluations.create_evidence_snapshot(PilotConformance.snapshot())

    assert has_limit_issue?(
             issues,
             ["payload", "comparisons", 0, "evidence", "attack_seeds"],
             11,
             12
           )

    assert Repo.aggregate(EvidenceSnapshot, :count) == count
  end

  test "PERSIST-12: a candidate request that exceeds its limit fails before a Gust run" do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(gust_owner) end)

    {:ok, snapshot} = Evaluations.create_evidence_snapshot(PilotConformance.snapshot())
    request = PilotConformance.request_params(snapshot.id)

    _ = Gust.Flows.create_dag(%{name: "evaluation_pilot"})
    assert Gust.Flows.get_dag_by_name("evaluation_pilot")

    with_limit(:candidate_request_bytes, 100)
    runs_before = Gust.Repo.aggregate(Gust.Flows.Run, :count)

    assert {:error, %PilotError{code: "request_too_large"}} = Evaluations.submit_pilot(request)

    assert Gust.Repo.aggregate(Gust.Flows.Run, :count) == runs_before
  end

  test "PERSIST-07: a snapshot whose study revision differs from the request is rejected" do
    {:ok, snapshot} = Evaluations.create_evidence_snapshot(PilotConformance.snapshot())
    request = PilotConformance.parsed_request(%{"snapshot_id" => snapshot.id})

    {:ok, _snapshot, payload} = EvidenceSnapshots.load(snapshot.id)

    other_revision =
      %{request | study_revision_id: Ecto.UUID.generate()}

    assert {:error, %PilotError{issues: issues}} =
             PilotRequest.matches_snapshot(other_revision, snapshot, payload)

    assert Enum.any?(issues, &(&1["code"] == "changed_snapshot"))
  end

  defp with_limit(limit, value) do
    original = Application.get_env(:network_defense, Limits)
    Application.put_env(:network_defense, Limits, Keyword.put(original, limit, value))
    on_exit(fn -> Application.put_env(:network_defense, Limits, original) end)
  end

  defp snapshot_with_plan_rows(alternative_rows, reference_rows) do
    update_in(
      PilotConformance.snapshot(),
      ["payload", "comparisons"],
      fn comparisons ->
        Enum.map(comparisons, fn comparison ->
          comparison
          |> put_in(
            ["evidence", "alternative", "plans"],
            Enum.take(comparison["evidence"]["alternative"]["plans"], alternative_rows)
          )
          |> put_in(
            ["evidence", "reference", "plans"],
            Enum.take(comparison["evidence"]["reference"]["plans"], reference_rows)
          )
        end)
      end
    )
  end

  defp has_limit_issue?(issues, path, limit, actual) do
    Enum.any?(issues, fn issue ->
      issue["code"] == "invalid_analysis_setting" and issue["path"] == path and
        issue["details"] == %{"limit" => limit, "actual" => actual}
    end)
  end
end
