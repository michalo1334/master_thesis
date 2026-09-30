defmodule NetworkDefenseWeb.StudyRunnerContractsTest do
  use ExUnit.Case, async: true

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.CloseStudyDocumentPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.CloseStudyDocumentReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ListStudyTierRunsPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ListStudyTierRunsReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.PreflightStudyPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.PreflightStudyReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StartStudyAnalysisPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StartStudyAnalysisReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyAnalysisErrorEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyAnalysisProgressEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyAnalysisReadyEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyRunError
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyTierRunSummary
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyTierSelection

  @document_id "00000000-0000-0000-0000-0000000000d1"
  @specification_id "00000000-0000-0000-0000-0000000000a1"
  @run_id "00000000-0000-0000-0000-0000000000f1"
  @attempt_id "dGhpcy1pc2FuLWF0dGVtcHQ"

  test "validates a tier selection and its run summary" do
    assert {:ok, %StudyTierSelection{tier: "small"}} =
             StudyTierSelection.validate(%{"tier" => "small", "run_id" => @run_id})

    assert {:error, changeset} = StudyTierSelection.validate(%{"tier" => "small"})
    assert %{run_id: ["can't be blank"]} = errors_on(changeset)

    assert {:error, changeset} =
             StudyTierSelection.validate(%{"tier" => "small", "run_id" => "not-a-uuid"})

    assert %{run_id: ["is invalid"]} = errors_on(changeset)

    assert {:ok, summary} =
             StudyTierRunSummary.validate(%{
               "id" => @run_id,
               "manifest_id" => "manifest-1",
               "manifest_title" => "T",
               "graph_title" => "G",
               "completed_at" => "2026-09-29T00:00:00Z",
               "plan_count" => 2,
               "trial_count" => 6
             })

    assert %{plan_count: 2, trial_count: 6} = StudyTierRunSummary.to_wire(summary)
    assert {:error, changeset} = StudyTierRunSummary.validate(%{"plan_count" => -1})

    assert %{id: ["can't be blank"], plan_count: ["must be greater than or equal to 0"]} =
             errors_on(changeset)
  end

  test "validates the scoped eligible run listing payload and reply" do
    assert {:ok, %ListStudyTierRunsPayload{tier: "small", mode: "pilot"}} =
             ListStudyTierRunsPayload.validate(%{
               "specification_id" => @specification_id,
               "tier" => "small",
               "mode" => "pilot"
             })

    assert %{enum_values: list_enums} = ListStudyTierRunsPayload.contract_meta()
    assert list_enums[:mode] == [:pilot, :final]

    assert {:error, changeset} = ListStudyTierRunsPayload.validate(%{})

    assert %{
             specification_id: ["can't be blank"],
             tier: ["can't be blank"],
             mode: ["can't be blank"]
           } =
             errors_on(changeset)

    assert {:error, changeset} =
             ListStudyTierRunsPayload.validate(%{
               "specification_id" => "not-a-uuid",
               "tier" => "small",
               "mode" => "pilot"
             })

    assert %{specification_id: ["is invalid"]} = errors_on(changeset)

    assert {:error, changeset} =
             ListStudyTierRunsPayload.validate(%{
               "specification_id" => @specification_id,
               "tier" => "small",
               "mode" => "analyze"
             })

    assert %{mode: ["is invalid"]} = errors_on(changeset)

    assert {:ok, reply} =
             ListStudyTierRunsReply.validate(%{
               "runs" => [%{"id" => @run_id, "plan_count" => 1, "trial_count" => 2}]
             })

    assert [%{id: @run_id}] = ListStudyTierRunsReply.to_wire(reply).runs
  end

  test "requires a specification, a mode, and at least one tier on preflight" do
    assert {:ok, payload} =
             PreflightStudyPayload.validate(%{
               "specification_id" => @specification_id,
               "mode" => "final",
               "tier_runs" => [%{"tier" => "small", "run_id" => @run_id}]
             })

    assert payload.mode == "final"
    assert [%{tier: "small", run_id: @run_id}] = payload.tier_runs

    assert %{enum_values: preflight_enums} = PreflightStudyPayload.contract_meta()
    assert preflight_enums[:mode] == [:pilot, :final]

    assert {:error, changeset} =
             PreflightStudyPayload.validate(%{"specification_id" => @specification_id})

    assert %{tier_runs: ["can't be blank"], mode: ["can't be blank"]} = errors_on(changeset)

    assert {:error, changeset} = PreflightStudyPayload.validate(%{"tier_runs" => []})

    assert %{specification_id: ["can't be blank"], mode: ["can't be blank"]} =
             errors_on(changeset)
  end

  test "validates the preflight reply with a stable error code" do
    assert {:ok, reply} =
             PreflightStudyReply.validate(%{
               "status" => "ok",
               "study_id" => "topology-scale-study",
               "specification_version" => 1,
               "tier_count" => 2,
               "errors" => []
             })

    assert %{status: "ok", tier_count: 2} = PreflightStudyReply.to_wire(reply)

    assert {:ok, %{status: "rejected", errors: [%{code: "run_not_found"}]}} =
             PreflightStudyReply.validate(%{
               "status" => "rejected",
               "errors" => [%{"code" => "run_not_found"}]
             })

    assert %{enum_values: enum_values} = PreflightStudyReply.contract_meta()
    assert enum_values[:status] == [:ok, :rejected, :invalid_request]

    assert {:error, changeset} = PreflightStudyReply.validate(%{"status" => "bogus"})
    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "validates the start payload with both modes" do
    assert {:ok, %StartStudyAnalysisPayload{mode: "pilot"}} =
             StartStudyAnalysisPayload.validate(%{
               "document_id" => @document_id,
               "specification_id" => @specification_id,
               "mode" => "pilot",
               "tier_runs" => [%{"tier" => "small", "run_id" => @run_id}]
             })

    assert {:ok, %StartStudyAnalysisPayload{mode: "final", specification_id: nil}} =
             StartStudyAnalysisPayload.validate(%{
               "document_id" => @document_id,
               "mode" => "final"
             })

    assert %{enum_values: enum_values} = StartStudyAnalysisPayload.contract_meta()
    assert enum_values[:mode] == [:pilot, :final]

    assert {:error, changeset} =
             StartStudyAnalysisPayload.validate(%{
               "document_id" => @document_id,
               "mode" => "analyze"
             })

    assert %{mode: ["is invalid"]} = errors_on(changeset)

    assert {:error, changeset} =
             StartStudyAnalysisPayload.validate(%{
               "document_id" => @document_id,
               "specification_id" => "not-a-uuid",
               "mode" => "pilot"
             })

    assert %{specification_id: ["is invalid"]} = errors_on(changeset)
  end

  test "validates the start reply with an optional mode" do
    assert {:ok, reply} =
             StartStudyAnalysisReply.validate(%{
               "status" => "accepted",
               "document_id" => @document_id,
               "mode" => "pilot",
               "attempt_id" => @attempt_id,
               "errors" => []
             })

    assert %{status: "accepted", mode: "pilot", attempt_id: @attempt_id} =
             StartStudyAnalysisReply.to_wire(reply)

    assert {:ok, %{status: "invalid_request", document_id: nil, attempt_id: nil}} =
             StartStudyAnalysisReply.validate(%{"status" => "invalid_request"})

    assert {:ok, %{status: "rejected", errors: [%{code: "already_running"}]}} =
             StartStudyAnalysisReply.validate(%{
               "status" => "rejected",
               "document_id" => @document_id,
               "mode" => "pilot",
               "errors" => [%{"code" => "already_running"}]
             })

    assert {:error, changeset} =
             StartStudyAnalysisReply.validate(%{
               "status" => "accepted",
               "document_id" => @document_id,
               "mode" => "pilot",
               "errors" => []
             })

    assert %{attempt_id: ["is required for an accepted reply"]} = errors_on(changeset)

    assert {:error, changeset} =
             StartStudyAnalysisReply.validate(%{
               "status" => "rejected",
               "document_id" => @document_id,
               "mode" => "pilot",
               "attempt_id" => @attempt_id,
               "errors" => [%{"code" => "already_running"}]
             })

    assert %{attempt_id: ["must be empty unless the reply is accepted"]} = errors_on(changeset)
  end

  test "validates the close payload and reply" do
    assert {:ok, %CloseStudyDocumentPayload{document_id: @document_id}} =
             CloseStudyDocumentPayload.validate(%{"document_id" => @document_id})

    assert {:error, changeset} = CloseStudyDocumentPayload.validate(%{"document_id" => "bad"})
    assert %{document_id: ["is invalid"]} = errors_on(changeset)

    for status <- ["closed", "not_found", "invalid_request"] do
      assert {:ok, %{status: ^status}} = CloseStudyDocumentReply.validate(%{"status" => status})
    end

    assert {:error, changeset} = CloseStudyDocumentReply.validate(%{"status" => "bogus"})
    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "rejects unknown study error codes" do
    assert {:ok, %{code: "transport"}} = StudyRunError.validate(%{"code" => "transport"})

    assert {:error, changeset} = StudyRunError.validate(%{"code" => "bogus"})
    assert %{code: ["is invalid"]} = errors_on(changeset)

    assert %{enum_values: enum_values} = StudyRunError.contract_meta()
    assert :internal_error in enum_values[:code]
    assert :already_running in enum_values[:code]
    assert :run_overlap in enum_values[:code]
    assert :result_too_large in enum_values[:code]
  end

  test "validates progress, ready, and error events" do
    assert {:ok, %{phase: "building_bundle"}} =
             StudyAnalysisProgressEvent.validate(%{
               "document_id" => @document_id,
               "mode" => "pilot",
               "attempt_id" => @attempt_id,
               "phase" => "building_bundle"
             })

    assert {:error, changeset} =
             StudyAnalysisProgressEvent.validate(%{
               "document_id" => @document_id,
               "mode" => "pilot",
               "phase" => "building_bundle"
             })

    assert %{attempt_id: ["can't be blank"]} = errors_on(changeset)

    assert %{enum_values: enum_values} = StudyAnalysisProgressEvent.contract_meta()

    assert enum_values[:phase] ==
             [
               :building_bundle,
               :submitting_analysis,
               :waiting_for_service,
               :validating_result,
               :complete
             ]

    assert {:error, changeset} =
             StudyAnalysisProgressEvent.validate(%{
               "document_id" => @document_id,
               "mode" => "pilot",
               "attempt_id" => @attempt_id,
               "phase" => "halfway"
             })

    assert %{phase: ["is invalid"]} = errors_on(changeset)

    assert {:ok, reply} =
             StudyAnalysisReadyEvent.validate(%{
               "document_id" => @document_id,
               "mode" => "pilot",
               "attempt_id" => @attempt_id,
               "archive" => "emlw",
               "pilot_eligible" => true,
               "analysis" => %{
                 "metadata" => %{
                   "study_id" => "topology-scale-study",
                   "specification_version" => 1,
                   "family_scope" => "study",
                   "family_size" => 1,
                   "command_mode" => "study-pilot"
                 }
               }
             })

    assert %{archive: "emlw", pilot_eligible: true, attempt_id: @attempt_id} =
             StudyAnalysisReadyEvent.to_wire(reply)

    assert {:ok, %{pilot_eligible: nil}} =
             StudyAnalysisReadyEvent.validate(%{
               "document_id" => @document_id,
               "mode" => "final",
               "attempt_id" => @attempt_id,
               "archive" => "emlw",
               "analysis" => %{
                 "metadata" => %{
                   "study_id" => "topology-scale-study",
                   "specification_version" => 1,
                   "family_scope" => "study",
                   "family_size" => 1,
                   "command_mode" => "study-analyze"
                 }
               }
             })

    assert {:ok, %{phase: "waiting_for_service"}} =
             StudyAnalysisErrorEvent.validate(%{
               "document_id" => @document_id,
               "mode" => "final",
               "attempt_id" => @attempt_id,
               "phase" => "waiting_for_service",
               "error" => %{"code" => "transport"}
             })

    assert {:ok, %{phase: nil}} =
             StudyAnalysisErrorEvent.validate(%{
               "document_id" => @document_id,
               "mode" => "pilot",
               "attempt_id" => @attempt_id,
               "error" => %{"code" => "internal_error"}
             })
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, &replace_error_option/2)
    end)
  end

  defp replace_error_option({key, value}, message) do
    placeholder = "%{#{key}}"

    if String.contains?(message, placeholder),
      do: String.replace(message, placeholder, to_string(value)),
      else: message
  end
end
