defmodule NetworkDefenseWeb.StudyTaskDeliveryTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.AnalysisClient
  alias NetworkDefense.Evaluation.AnalysisLimits
  alias NetworkDefense.EvaluationFixtures
  alias NetworkDefenseWeb.Dashboard.StudyCoordinator

  @document_id "00000000-0000-0000-0000-0000000000d2"

  setup do
    previous = Application.get_env(:network_defense, :analysis_service)
    on_exit(fn -> Application.put_env(:network_defense, :analysis_service, previous) end)

    manifest_id = "study-task-delivery-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             EvaluationFixtures.save_manifest(manifest_id, EvaluationFixtures.analysis_manifest())

    run = EvaluationFixtures.completed_run(manifest_id)

    specification =
      EvaluationFixtures.study_specification()
      |> Map.put("tiers", ["small"])

    assert {:ok, saved} = EvaluationFixtures.save_study_specification(specification)

    %{run: run, specification: saved}
  end

  test "an oversized archive never reaches the owner mailbox", %{
    run: run,
    specification: specification
  } do
    Application.put_env(:network_defense, :analysis_service, browser_result_bytes: 1)

    assert byte_size(EvaluationFixtures.study_result_archive("pilot")) >
             AnalysisLimits.browser_result_bytes()

    test_pid = self()

    :meck.new(AnalysisClient, [:passthrough])
    on_exit(fn -> :meck.unload() end)

    :meck.expect(AnalysisClient, :analyze_study, fn bundle, _study_id, :pilot ->
      archive = EvaluationFixtures.study_result_archive_for_bundle("pilot", bundle)
      send(test_pid, {:result_archive, archive})
      {:ok, archive}
    end)

    assert {:ok, _sessions, @document_id, attempt_id} =
             StudyCoordinator.start(%{}, :pilot, %{
               document_id: @document_id,
               specification_id: specification.id,
               tier_runs: [{"small", run.id}]
             })

    assert is_binary(attempt_id)
    assert attempt_id != ""

    assert_receive {:study_result, @document_id, ^attempt_id, result}, 5_000

    assert result == {:error, :result_too_large}
    assert_receive {:result_archive, archive}
    refute archive_bytes_present?(result, archive)
  end

  defp archive_bytes_present?(term, archive) do
    :binary.match(:erlang.term_to_binary(term), archive) != :nomatch
  end
end
