defmodule NetworkDefenseWeb.StudyCoordinatorTest do
  use ExUnit.Case, async: true

  @moduletag capture_log: true

  alias NetworkDefense.Evaluation.AnalysisLimits
  alias NetworkDefense.Evaluation.StudyAttempt
  alias NetworkDefense.Evaluation.StudySession
  alias NetworkDefenseWeb.Dashboard.StudyCoordinator

  @document_id "00000000-0000-0000-0000-0000000000d1"
  @pilot_run_id "00000000-0000-0000-0000-0000000000f1"
  @final_run_id "00000000-0000-0000-0000-0000000000f2"

  describe "final mapping" do
    test "rejects a final start without a mapping" do
      sessions = eligible_pilot()

      assert {:error, :invalid_request} =
               StudyCoordinator.start(sessions, :final, %{
                 document_id: @document_id,
                 tier_runs: []
               })
    end

    test "rejects a final mapping that reuses a pilot run" do
      sessions = eligible_pilot()

      assert {:error, :run_overlap} =
               StudyCoordinator.start(sessions, :final, %{
                 document_id: @document_id,
                 tier_runs: [{"small", @pilot_run_id}]
               })
    end

    test "rejects a final start without eligible pilot state" do
      sessions = %{@document_id => StudySession.new(locks())}

      assert {:error, :final_not_available} =
               StudyCoordinator.start(sessions, :final, %{
                 document_id: @document_id,
                 tier_runs: [{"small", @final_run_id}]
               })
    end

    test "rejects a changed mapping once the final mapping is locked" do
      session =
        eligible_pilot()
        |> Map.fetch!(@document_id)
        |> StudySession.lock_final([{"small", @final_run_id}])

      sessions = %{@document_id => session}

      assert {:error, :document_locked} =
               StudyCoordinator.start(sessions, :final, %{
                 document_id: @document_id,
                 tier_runs: [{"small", "other-run"}]
               })
    end
  end

  describe "terminal message ordering" do
    test "a consumed result ignores a later DOWN" do
      {sessions, ref, attempt_id} = active_pilot()

      {sessions, [ready]} =
        StudyCoordinator.handle_result(sessions, @document_id, attempt_id, {:ok, result()})

      assert {"study_analysis_ready", _, %{archive: archive, pilot_eligible: true}} = ready
      assert Base.decode64!(archive) == "zip"
      assert sessions[@document_id].pilot.eligible
      refute StudySession.running?(sessions[@document_id])

      {unchanged, []} = StudyCoordinator.handle_down(sessions, ref)
      assert unchanged == sessions
    end

    test "a DOWN first consumes the attempt and ignores the queued result" do
      {sessions, ref, attempt_id} = active_pilot()

      {sessions, [error]} = StudyCoordinator.handle_down(sessions, ref)
      assert {"study_analysis_error", _, %{error: %{code: "internal_error"}}} = error
      refute StudySession.running?(sessions[@document_id])

      {unchanged, []} =
        StudyCoordinator.handle_result(sessions, @document_id, attempt_id, {:ok, result()})

      assert unchanged == sessions
      assert sessions[@document_id].pilot == nil
    end

    test "a duplicate terminal result is stale" do
      {sessions, _ref, attempt_id} = active_pilot()

      {sessions, [_ready]} =
        StudyCoordinator.handle_result(sessions, @document_id, attempt_id, {:ok, result()})

      {unchanged, []} =
        StudyCoordinator.handle_result(sessions, @document_id, attempt_id, {:ok, result()})

      assert unchanged == sessions
    end

    test "maps a tuple failure reason to the invalid_result wire code" do
      {sessions, _ref, attempt_id} = active_pilot()

      {sessions, [error]} =
        StudyCoordinator.handle_result(
          sessions,
          @document_id,
          attempt_id,
          {:error, {:malformed, "member"}}
        )

      assert {"study_analysis_error", _, %{error: %{code: "invalid_result"}}} = error
      assert sessions[@document_id].error.reason == {:malformed, "member"}
    end

    test "a duplicate failure message is stale" do
      {sessions, _ref, attempt_id} = active_pilot()

      {sessions, [_error]} =
        StudyCoordinator.handle_result(sessions, @document_id, attempt_id, {:error, :transport})

      {unchanged, []} =
        StudyCoordinator.handle_result(sessions, @document_id, attempt_id, {:error, :transport})

      assert unchanged == sessions
      assert sessions[@document_id].error == %{reason: :transport, phase: :building_bundle}
    end
  end

  describe "crash transition" do
    test "a crash fails the attempt once and clears pilot eligibility" do
      {sessions, ref, _attempt_id} = active_pilot()

      {sessions, [error]} = StudyCoordinator.handle_down(sessions, ref)
      session = sessions[@document_id]

      assert {"study_analysis_error", _, %{phase: "building_bundle"}} = error
      assert session.error == %{reason: :internal_error, phase: :building_bundle}
      assert session.attempt == nil
      assert session.pilot == nil
      refute StudySession.final_allowed?(session)

      {unchanged, []} = StudyCoordinator.handle_down(sessions, ref)
      assert unchanged == sessions
    end
  end

  describe "stale attempts" do
    test "ignores phase, result, and DOWN messages from a replaced attempt" do
      {sessions, _ref, attempt_id} = active_pilot()
      stale_attempt = "stale-attempt"
      stale_ref = make_ref()

      {unchanged, []} =
        StudyCoordinator.handle_phase(sessions, @document_id, stale_attempt, :complete)

      assert unchanged == sessions

      {unchanged, []} =
        StudyCoordinator.handle_result(sessions, @document_id, stale_attempt, {:ok, result()})

      assert unchanged == sessions

      {unchanged, []} = StudyCoordinator.handle_down(sessions, stale_ref)
      assert unchanged == sessions

      {unchanged, []} =
        StudyCoordinator.handle_phase(sessions, "other-document", attempt_id, :complete)

      assert unchanged == sessions
    end

    test "a delayed result from a superseded same-mode attempt cannot settle a retry" do
      {sessions, _ref, first_attempt} = active_pilot()

      {sessions, [_error]} =
        StudyCoordinator.handle_result(
          sessions,
          @document_id,
          first_attempt,
          {:error, :transport}
        )

      session = sessions[@document_id]

      rerun =
        StudySession.start_attempt(
          session,
          StudyAttempt.new(StudyAttempt.new_id(), :pilot, self(), make_ref())
        )

      sessions = Map.put(sessions, @document_id, rerun)

      {unchanged, []} =
        StudyCoordinator.handle_result(sessions, @document_id, first_attempt, {:ok, result()})

      assert unchanged == sessions
      assert StudySession.running?(sessions[@document_id])
      refute StudySession.pilot_eligible?(sessions[@document_id])
    end
  end

  describe "phases" do
    test "a matching phase advances the session and pushes progress" do
      {sessions, _ref, attempt_id} = active_pilot()

      {sessions, [progress]} =
        StudyCoordinator.handle_phase(sessions, @document_id, attempt_id, :waiting_for_service)

      assert {"study_analysis_progress", _, %{phase: "waiting_for_service", mode: "pilot"}} =
               progress

      assert sessions[@document_id].phase == :waiting_for_service
    end
  end

  describe "browser result limit" do
    test "rejects a result larger than the browser delivery limit" do
      {sessions, _ref, attempt_id} = active_pilot()
      archive = :binary.copy(<<0>>, AnalysisLimits.browser_result_bytes() + 1)

      {sessions, [error]} =
        StudyCoordinator.handle_result(
          sessions,
          @document_id,
          attempt_id,
          {:ok, %{archive: archive, analysis: %{}, eligible: true}}
        )

      assert {"study_analysis_error", _,
              %{error: %{code: "result_too_large"}, phase: "building_bundle"}} = error

      assert sessions[@document_id].error.reason == :result_too_large
      refute StudySession.running?(sessions[@document_id])
      assert sessions[@document_id].pilot == nil
    end
  end

  describe "failed pilot rerun" do
    test "a failed pilot rerun denies the final gate" do
      {sessions, _ref, attempt_id} = active_pilot()

      {sessions, [_ready]} =
        StudyCoordinator.handle_result(sessions, @document_id, attempt_id, {:ok, result()})

      assert StudySession.final_allowed?(sessions[@document_id])

      rerun =
        StudySession.start_attempt(
          sessions[@document_id],
          StudyAttempt.new(StudyAttempt.new_id(), :pilot, self(), make_ref())
        )

      sessions = Map.put(sessions, @document_id, rerun)

      {sessions, [_error]} =
        StudyCoordinator.handle_result(
          sessions,
          @document_id,
          rerun.attempt.id,
          {:error, :transport}
        )

      refute StudySession.pilot_eligible?(sessions[@document_id])
      refute StudySession.final_allowed?(sessions[@document_id])
    end
  end

  describe "cancellation races" do
    test "close cancels an active attempt and reports a missing document" do
      {sessions, _ref, _attempt_id} = active_pilot()

      {remaining, :closed} = StudyCoordinator.close(sessions, @document_id)
      refute Map.has_key?(remaining, @document_id)

      {^remaining, :not_found} = StudyCoordinator.close(remaining, @document_id)
    end

    test "a result consumed before close leaves nothing to cancel" do
      {sessions, _ref, attempt_id} = active_pilot()

      {sessions, [_ready]} =
        StudyCoordinator.handle_result(sessions, @document_id, attempt_id, {:ok, result()})

      refute StudySession.running?(sessions[@document_id])

      {remaining, :closed} = StudyCoordinator.close(sessions, @document_id)
      refute Map.has_key?(remaining, @document_id)
    end

    test "terminate cancels every active attempt" do
      {sessions, _ref, _attempt_id} = active_pilot()
      assert :ok = StudyCoordinator.terminate(sessions)
    end
  end

  defp eligible_pilot do
    session =
      StudySession.new(locks())
      |> StudySession.start_attempt(
        StudyAttempt.new(StudyAttempt.new_id(), :pilot, self(), make_ref())
      )

    {:ok, session, _attempt} =
      StudySession.consume_result(session, StudySession.attempt_id(session), %{
        analysis: %{},
        eligible: true
      })

    %{@document_id => session}
  end

  defp active_pilot do
    {:ok, pid} =
      Task.Supervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
        Process.sleep(:infinity)
      end)

    ref = Process.monitor(pid)
    attempt = StudyAttempt.new(StudyAttempt.new_id(), :pilot, pid, ref)
    session = StudySession.new(locks()) |> StudySession.start_attempt(attempt)

    {%{@document_id => session}, ref, attempt.id}
  end

  defp result do
    %{archive: "zip", analysis: %{metadata: %{}}, eligible: true}
  end

  defp locks do
    %{
      document_id: @document_id,
      specification_id: "00000000-0000-0000-0000-0000000000a1",
      study_id: "topology-scale-study",
      specification_version: 1,
      tier_runs: [{"small", @pilot_run_id}]
    }
  end
end
