defmodule NetworkDefense.Evaluation.StudySessionTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.StudyAttempt
  alias NetworkDefense.Evaluation.StudySession

  @locks %{
    document_id: "00000000-0000-0000-0000-0000000000d1",
    specification_id: "00000000-0000-0000-0000-0000000000a1",
    study_id: "topology-scale-study",
    specification_version: 1,
    tier_runs: [{"small", "00000000-0000-0000-0000-0000000000f1"}]
  }

  @final_tier_runs [{"small", "00000000-0000-0000-0000-0000000000f2"}]

  test "locks the specification and the exact tier mapping" do
    session = StudySession.new(@locks)

    assert StudySession.matches_locks?(session, @locks.specification_id, @locks.tier_runs)
    refute StudySession.matches_locks?(session, @locks.specification_id, [{"small", "other"}])
    refute StudySession.matches_locks?(session, "other-specification", @locks.tier_runs)
  end

  test "starts one typed attempt and tracks its identity and phase" do
    session = @locks |> StudySession.new() |> StudySession.start_attempt(attempt(:pilot))

    assert StudySession.running?(session)
    assert session.mode == :pilot
    assert session.phase == :building_bundle
    assert %StudyAttempt{mode: :pilot} = StudySession.attempt(session)

    assert {:ok, session} =
             StudySession.set_phase(
               session,
               StudySession.attempt_id(session),
               :waiting_for_service
             )

    assert session.phase == :waiting_for_service
  end

  test "keeps a dead but unconsumed attempt active" do
    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

    session =
      @locks |> StudySession.new() |> StudySession.start_attempt(attempt(:pilot, pid, ref))

    assert StudySession.running?(session)
    assert StudySession.attempt_id(session) != nil
  end

  test "ignores a phase for a stale attempt identity" do
    session = @locks |> StudySession.new() |> StudySession.start_attempt(attempt(:pilot))

    assert :stale = StudySession.set_phase(session, "stale-attempt", :complete)
  end

  test "consumes one result and returns the consumed attempt" do
    session = @locks |> StudySession.new() |> StudySession.start_attempt(attempt(:pilot))
    attempt_id = StudySession.attempt_id(session)

    assert {:ok, session, %StudyAttempt{mode: :pilot}} =
             StudySession.consume_result(session, attempt_id, %{analysis: %{}, eligible: true})

    refute StudySession.running?(session)
    assert session.pilot == %{analysis: %{}, eligible: true}
    assert session.phase == :complete

    assert :stale =
             StudySession.consume_result(session, attempt_id, %{analysis: %{}, eligible: true})
  end

  test "a superseded same-mode attempt cannot settle a retry" do
    session = @locks |> StudySession.new() |> StudySession.start_attempt(attempt(:pilot))
    first_attempt = StudySession.attempt_id(session)

    failed =
      session
      |> then(&StudySession.consume_failure(&1, first_attempt, :transport))
      |> elem(1)

    retry = StudySession.start_attempt(failed, attempt(:pilot))

    assert :stale =
             StudySession.consume_result(retry, first_attempt, %{analysis: %{}, eligible: true})

    refute StudySession.pilot_eligible?(retry)
    refute StudySession.final_allowed?(retry)
    assert StudySession.running?(retry)
  end

  test "keeps locked inputs and the last phase after a failure" do
    session =
      @locks
      |> StudySession.new()
      |> StudySession.start_attempt(attempt(:pilot))
      |> then(
        &elem(StudySession.set_phase(&1, StudySession.attempt_id(&1), :waiting_for_service), 1)
      )

    assert {:ok, session, %StudyAttempt{}} =
             StudySession.consume_failure(session, StudySession.attempt_id(session), :transport)

    assert session.attempt == nil
    assert session.error == %{reason: :transport, phase: :waiting_for_service}
    assert session.tier_runs == @locks.tier_runs
    refute StudySession.running?(session)
  end

  test "records a tuple failure reason without losing the attempt" do
    session = @locks |> StudySession.new() |> StudySession.start_attempt(attempt(:pilot))

    assert {:ok, session, %StudyAttempt{}} =
             StudySession.consume_failure(
               session,
               StudySession.attempt_id(session),
               {:zip, :bad}
             )

    assert session.error.reason == {:zip, :bad}
    refute StudySession.running?(session)
  end

  test "an eligible pilot allows final and stores the final result separately" do
    session =
      @locks
      |> StudySession.new()
      |> StudySession.start_attempt(attempt(:pilot))
      |> consume(:pilot, %{analysis: %{}, eligible: true})

    assert StudySession.pilot_eligible?(session)
    assert StudySession.final_allowed?(session)

    session =
      session
      |> StudySession.start_attempt(attempt(:final))
      |> consume(:final, %{analysis: %{}, eligible: nil})

    assert session.final == %{analysis: %{}, eligible: nil}
    assert session.pilot == %{analysis: %{}, eligible: true}
    refute StudySession.final_allowed?(session)
  end

  test "an ineligible pilot keeps final disabled but permits a rerun" do
    session =
      @locks
      |> StudySession.new()
      |> StudySession.start_attempt(attempt(:pilot))
      |> consume(:pilot, %{analysis: %{}, eligible: false})

    refute StudySession.final_allowed?(session)

    rerun = StudySession.start_attempt(session, attempt(:pilot))
    assert StudySession.running?(rerun)
    assert rerun.tier_runs == @locks.tier_runs
  end

  test "a new pilot attempt invalidates earlier eligibility and its final" do
    session =
      @locks
      |> StudySession.new()
      |> StudySession.start_attempt(attempt(:pilot))
      |> consume(:pilot, %{analysis: %{}, eligible: true})
      |> StudySession.start_attempt(attempt(:final))
      |> consume(:final, %{analysis: %{}, eligible: nil})

    refute StudySession.final_allowed?(session)

    session = StudySession.start_attempt(session, attempt(:pilot))

    refute StudySession.pilot_eligible?(session)
    assert session.pilot == nil
    assert session.final == nil
    refute StudySession.final_allowed?(session)
  end

  test "a failed pilot rerun invalidates eligibility, a failed final keeps it" do
    session =
      @locks
      |> StudySession.new()
      |> StudySession.start_attempt(attempt(:pilot))
      |> consume(:pilot, %{analysis: %{}, eligible: true})

    failed_pilot =
      session
      |> StudySession.start_attempt(attempt(:pilot))
      |> then(&consume_failure(&1, :transport))

    refute StudySession.pilot_eligible?(failed_pilot)
    refute StudySession.final_allowed?(failed_pilot)

    failed_final =
      session
      |> StudySession.start_attempt(attempt(:final))
      |> then(&consume_failure(&1, :transport))

    assert StudySession.pilot_eligible?(failed_final)
    assert StudySession.final_allowed?(failed_final)
  end

  test "an active attempt blocks final even after an eligible pilot" do
    session =
      @locks
      |> StudySession.new()
      |> StudySession.start_attempt(attempt(:pilot))
      |> consume(:pilot, %{analysis: %{}, eligible: true})
      |> StudySession.start_attempt(attempt(:final))

    refute StudySession.final_allowed?(session)
  end

  test "cancel returns the attempt once and a consumed session cancels nothing" do
    session = @locks |> StudySession.new() |> StudySession.start_attempt(attempt(:pilot))

    {session, %StudyAttempt{}} = StudySession.cancel(session)
    assert StudySession.attempt(session) == nil
    assert {_session, nil} = StudySession.cancel(session)

    completed =
      @locks
      |> StudySession.new()
      |> StudySession.start_attempt(attempt(:pilot))
      |> consume(:pilot, %{analysis: %{}, eligible: true})

    assert {_session, nil} = StudySession.cancel(completed)
  end

  test "locks the final mapping once and reports overlap with the pilot mapping" do
    session = StudySession.new(@locks)

    refute StudySession.final_mapping_locked?(session)
    assert StudySession.mode_tier_runs(session, :final) == []
    assert StudySession.mode_tier_runs(session, :pilot) == @locks.tier_runs

    refute StudySession.overlaps_pilot?(session, @final_tier_runs)
    assert StudySession.overlaps_pilot?(session, @locks.tier_runs)

    locked = StudySession.lock_final(session, @final_tier_runs)

    assert StudySession.final_mapping_locked?(locked)
    assert StudySession.final_tier_runs(locked) == @final_tier_runs
    assert StudySession.mode_tier_runs(locked, :final) == @final_tier_runs

    assert StudySession.lock_final(locked, [{"small", "other"}]).final_tier_runs ==
             @final_tier_runs
  end

  test "a new pilot attempt clears the locked final mapping" do
    session =
      @locks
      |> StudySession.new()
      |> StudySession.lock_final(@final_tier_runs)
      |> StudySession.start_attempt(attempt(:pilot))

    refute StudySession.final_mapping_locked?(session)
    assert StudySession.final_tier_runs(session) == nil
  end

  test "consume down matches the monitor reference only" do
    session = @locks |> StudySession.new() |> StudySession.start_attempt(attempt(:pilot))
    ref = StudySession.attempt(session).ref

    assert :stale = StudySession.consume_down(session, make_ref())

    assert {:ok, session, %StudyAttempt{}} = StudySession.consume_down(session, ref)

    assert session.error == %{reason: :internal_error, phase: :building_bundle}
    refute StudySession.running?(session)
  end

  defp attempt(mode, pid \\ nil, ref \\ nil) do
    StudyAttempt.new(StudyAttempt.new_id(), mode, pid || self(), ref || make_ref())
  end

  defp consume(session, mode, result) do
    {:ok, session, %StudyAttempt{mode: ^mode}} =
      StudySession.consume_result(session, StudySession.attempt_id(session), result)

    session
  end

  defp consume_failure(session, reason) do
    {:ok, session, %StudyAttempt{}} =
      StudySession.consume_failure(session, StudySession.attempt_id(session), reason)

    session
  end
end
