defmodule NetworkDefense.Evaluation.Final.WorkflowApiTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox

  alias NetworkDefense.Evaluation.EvidenceSnapshot

  alias NetworkDefense.Evaluation.Final.Contracts.{
    FinalError,
    Result,
    SnapshotInput,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Final.Limits
  alias NetworkDefense.Evaluation.FinalComputeStub
  alias NetworkDefense.Evaluation.FinalConformance
  alias NetworkDefense.Evaluation.Pilot.Limits, as: PilotLimits
  alias NetworkDefense.Evaluations
  alias NetworkDefense.Repo

  # Acceptance coverage in this file:
  #   S5-01  one typed Final snapshot is created and read back
  #   S5-09  read-back validates the stored payload and metadata
  #   S5-10  assertions stay labelled as caller-asserted data
  #
  # Review finding P2 (snapshot creation and await input validation): creation
  # returns the stored representation read back through the validated path, and
  # the public Final functions reject malformed identifiers and timeouts with a
  # bounded typed error instead of raising.

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    owner = Sandbox.start_owner!(Repo, shared: true)

    on_exit(fn ->
      Sandbox.stop_owner(owner)
      Sandbox.stop_owner(gust_owner)
    end)

    :ok = FinalComputeStub.start_gust!()
    _agent = FinalComputeStub.start!()
    pilot_run_id = FinalComputeStub.recommended_pilot_run!()

    %{pilot_run_id: pilot_run_id}
  end

  describe "snapshot creation" do
    test "API-01: creation returns the stored representation", %{} do
      assert {:ok, created} =
               Evaluations.create_final_evidence_snapshot(FinalConformance.snapshot())

      assert {:ok, stored} = Evaluations.get_final_evidence_snapshot(created.id)

      assert created == stored
      assert created.phase == :final
      assert created.schema_version == 1
      assert created.family_id == "family-example"
      assert created.study_revision_id == FinalConformance.snapshot()["study_revision_id"]
    end

    test "API-02: the returned payload is the stored JSONB representation", %{} do
      assert {:ok, snapshot} =
               Evaluations.create_final_evidence_snapshot(FinalConformance.snapshot())

      assert %{"schema_version" => 1, "evidence_role" => "final"} = snapshot.payload
      assert [first | _rest] = snapshot.payload["comparisons"]
      assert is_binary(first["identity"]["tier"])
      assert %DateTime{} = snapshot.inserted_at
    end

    test "API-03: reads do not apply the create-time storage byte limit", %{} do
      assert {:ok, snapshot} =
               Evaluations.create_final_evidence_snapshot(FinalConformance.snapshot())

      with_snapshot_limit(1)

      assert {:ok, loaded} = Evaluations.get_final_evidence_snapshot(snapshot.id)
      assert loaded == snapshot
    end

    test "API-04: create accepts below and at the storage byte limit and rejects above it", %{} do
      attrs = FinalConformance.snapshot()
      bytes = stored_payload_size(attrs)
      count = Repo.aggregate(EvidenceSnapshot, :count)

      with_snapshot_limit(bytes + 1)
      assert {:ok, _snapshot} = Evaluations.create_final_evidence_snapshot(attrs)
      assert Repo.aggregate(EvidenceSnapshot, :count) == count + 1

      with_snapshot_limit(bytes)
      assert {:ok, _snapshot} = Evaluations.create_final_evidence_snapshot(attrs)
      assert Repo.aggregate(EvidenceSnapshot, :count) == count + 2

      with_snapshot_limit(bytes - 1)
      assert {:ok, %SnapshotInput{}} = SnapshotInput.parse(attrs)

      assert {:error, %FinalError{code: "request_too_large", issues: [issue]}} =
               Evaluations.create_final_evidence_snapshot(attrs)

      assert issue["details"] == %{"limit_bytes" => bytes - 1, "actual_bytes" => bytes}
      assert Repo.aggregate(EvidenceSnapshot, :count) == count + 2
    end

    test "API-04b: a non-JSON snapshot value is rejected before insert", %{} do
      count = Repo.aggregate(EvidenceSnapshot, :count)

      attrs =
        put_in(
          FinalConformance.snapshot(),
          ["payload", "comparisons", Access.at(0), "evidence", "attack_seeds", Access.at(0)],
          :not_json
        )

      assert {:error, %FinalError{code: "validation_failed", issues: [issue]}} =
               Evaluations.create_final_evidence_snapshot(attrs)

      assert issue["code"] == "invalid_type"
      assert Repo.aggregate(EvidenceSnapshot, :count) == count
    end
  end

  defp with_snapshot_limit(value) do
    original = Application.fetch_env!(:network_defense, PilotLimits)

    Application.put_env(
      :network_defense,
      PilotLimits,
      Keyword.put(original, :snapshot_payload_bytes, value)
    )

    on_exit(fn -> Application.put_env(:network_defense, PilotLimits, original) end)
  end

  defp stored_payload_size(attrs) do
    assert {:ok, input} = SnapshotInput.parse(attrs)
    assert {:ok, encoded} = Jason.encode_to_iodata(SnapshotPayload.to_params(input.payload))
    IO.iodata_length(encoded)
  end

  describe "public input validation" do
    test "API-05: a malformed run identifier returns a typed error", %{} do
      for value <- [nil, "abc", 0, -1, 1.5, :run, %{}, []] do
        assert {:error, %FinalError{code: "validation_failed", issues: [issue]}} =
                 Evaluations.await_final(value, 100),
               "expected a bounded error for #{inspect(value)}"

        assert issue["code"] == "invalid_argument"

        assert {:error, %FinalError{issues: [result_issue]}} =
                 Evaluations.get_final_result(value),
               "expected a bounded error for #{inspect(value)}"

        assert result_issue["code"] == "invalid_argument"
      end
    end

    test "API-06: a malformed timeout returns a typed error" do
      for value <- [nil, "soon", -1, 1.5, :forever, %{}] do
        assert {:error, %FinalError{code: "validation_failed", issues: [issue]}} =
                 Evaluations.await_final(1, value),
               "expected a bounded error for #{inspect(value)}"

        assert issue["code"] == "invalid_argument"
      end
    end

    test "API-07: an unknown but well-formed run identifier is not found", %{} do
      unknown = System.unique_integer([:positive]) + 9_000_000

      assert {:error, :not_found} = Evaluations.await_final(unknown, 1_000)
      assert {:error, :not_found} = Evaluations.get_final_result(unknown)
    end
  end

  describe "await and read" do
    test "API-08: await reports status only and the result comes from read", %{
      pilot_run_id: pilot_run_id
    } do
      assert {:ok, snapshot} =
               Evaluations.create_final_evidence_snapshot(FinalConformance.snapshot())

      params = FinalConformance.request_params!(snapshot.id, pilot_run_id)

      assert {:ok, run_id} = Evaluations.submit_final(params)
      assert {:ok, :succeeded} = Evaluations.await_final(run_id, 20_000)
      assert {:ok, :succeeded} = Evaluations.await_final(run_id, 0)

      assert {:ok, %Result{} = result} = Evaluations.get_final_result(run_id)
      assert result.snapshot_id == snapshot.id
      assert result.evidence_role == "final"
      assert result.assertion_basis == "caller_asserted"
    end

    test "API-09: the configured limits are explicit and positive", %{} do
      assert {:ok, limits} = Limits.fetch()
      assert limits.max_bootstrap_replicates > 0
      assert limits.max_total_work > 0
    end
  end
end
