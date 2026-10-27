defmodule NetworkDefense.Evaluation.Study.StudyPhaseRunsTest do
  use NetworkDefense.DataCase, async: false

  @moduletag :integration

  alias Ecto.UUID
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.PhaseRuns
  alias NetworkDefense.Evaluation.StudyFixtures
  alias NetworkDefense.Evaluation.{StudyPhase, StudyPhaseRun}

  setup do
    StudyFixtures.study_with_two_phases()
  end

  test "PHASE-RUN-01: WHEN an identity is requested twice, THE store SHALL return one row", %{
    final_phase: phase
  } do
    assert {:ok, first} = PhaseRuns.get_or_create(phase, "core", 0)
    assert {:ok, second} = PhaseRuns.get_or_create(phase, "core", 0)
    assert first.id == second.id

    assert {:error, %StudyError{code: "conflict"}} = PhaseRuns.get_or_create(phase, "edge", 0)
    assert {:error, %StudyError{code: "conflict"}} = PhaseRuns.get_or_create(phase, "core", 1)
  end

  test "PHASE-RUN-02: WHEN a run is linked again, THE store SHALL accept only the same run", %{
    final_phase: phase
  } do
    assert {:ok, run} = PhaseRuns.get_or_create(phase, "core", 0)
    assert {:ok, linked} = PhaseRuns.link_gust_run(run, 101)
    assert {:ok, repeated} = PhaseRuns.link_gust_run(run, 101)
    assert linked.id == repeated.id
    assert {:error, %StudyError{code: "conflict"}} = PhaseRuns.link_gust_run(run, 102)
  end

  test "PHASE-RUN-03: WHEN tier runs are read, THE store SHALL order them and reject missing links",
       %{final_phase: phase} do
    assert {:ok, edge} = PhaseRuns.get_or_create(phase, "edge", 1)
    assert {:ok, core} = PhaseRuns.get_or_create(phase, "core", 0)
    assert {:ok, rows} = PhaseRuns.ordered_for_phase(phase.id)
    assert Enum.map(rows, & &1.tier) == ["core", "edge"]
    assert {:error, %StudyError{}} = PhaseRuns.ordered_run_ids(phase.id)
    assert {:ok, _} = PhaseRuns.link_gust_run(edge, 102)
    assert {:ok, _} = PhaseRuns.link_gust_run(core, 101)
    assert {:ok, [101, 102]} = PhaseRuns.ordered_run_ids(phase.id)
  end

  test "PHASE-RUN-04: WHEN Pilot and Final runs are linked, THE store SHALL persist each phase independently",
       %{pilot_phase: pilot_phase, final_phase: final_phase} do
    assert {:ok, pilot} = PhaseRuns.get_or_create(pilot_phase, "core", 0)
    assert {:ok, final} = PhaseRuns.get_or_create(final_phase, "core", 0)
    assert {:ok, _} = PhaseRuns.link_gust_run(pilot, 701)
    assert {:ok, _} = PhaseRuns.link_gust_run(final, 702)

    assert %StudyPhaseRun{study_phase_id: pilot_phase_id, gust_run_id: 701} =
             Repo.get!(StudyPhaseRun, pilot.id)

    assert pilot_phase_id == pilot_phase.id

    assert %StudyPhaseRun{study_phase_id: final_phase_id, gust_run_id: 702} =
             Repo.get!(StudyPhaseRun, final.id)

    assert final_phase_id == final_phase.id
    assert {:ok, [701]} = PhaseRuns.ordered_run_ids(pilot_phase.id)
    assert {:ok, [702]} = PhaseRuns.ordered_run_ids(final_phase.id)
  end

  test "PHASE-RUN-05: WHEN a phase has no runs, THE store SHALL reject its run list as incomplete",
       %{final_phase: phase} do
    assert {:error, %StudyError{issues: [%{"code" => "incomplete_phase_run_list"}]}} =
             PhaseRuns.ordered_for_phase(phase.id)

    assert {:error, %StudyError{issues: [%{"code" => "incomplete_phase_run_list"}]}} =
             PhaseRuns.ordered_run_ids(phase.id)
  end

  test "PHASE-RUN-06: WHEN phase-run positions have a gap, THE store SHALL reject the run list as incomplete",
       %{final_phase: phase} do
    assert {:ok, first} = PhaseRuns.get_or_create(phase, "core", 0)
    assert {:ok, third} = PhaseRuns.get_or_create(phase, "edge", 2)
    assert {:ok, _} = PhaseRuns.link_gust_run(first, 711)
    assert {:ok, _} = PhaseRuns.link_gust_run(third, 713)

    assert {:error, %StudyError{issues: [%{"code" => "incomplete_phase_run_list"}]}} =
             PhaseRuns.ordered_for_phase(phase.id)

    assert {:error, %StudyError{issues: [%{"code" => "incomplete_phase_run_list"}]}} =
             PhaseRuns.ordered_run_ids(phase.id)
  end

  test "PHASE-RUN-11: WHEN the first tier position is missing, THE store SHALL reject the family",
       %{final_phase: phase} do
    assert {:ok, run} = PhaseRuns.get_or_create(phase, "edge", 1)
    assert {:ok, _} = PhaseRuns.link_gust_run(run, 714)

    assert {:error, %StudyError{issues: [%{"code" => "incomplete_phase_run_list"}]}} =
             PhaseRuns.ordered_for_phase(phase.id)

    assert {:error, %StudyError{issues: [%{"code" => "incomplete_phase_run_list"}]}} =
             PhaseRuns.ordered_run_ids(phase.id)
  end

  test "PHASE-RUN-07: WHEN a tier is blank, THE store SHALL reject the phase run",
       %{final_phase: phase} do
    for tier <- ["", " ", "\t", "\n"] do
      assert {:error,
              %StudyError{
                code: "validation_failed",
                issues: [%{"code" => "invalid_tier"}]
              }} = PhaseRuns.get_or_create(phase, tier, 0)
    end

    assert {:error, %StudyError{}} = PhaseRuns.ordered_for_phase(phase.id)
  end

  test "PHASE-RUN-08: WHEN a Gust ID is already linked, THE store SHALL reject another phase link",
       %{pilot_phase: pilot_phase, final_phase: final_phase} do
    assert {:ok, pilot} = PhaseRuns.get_or_create(pilot_phase, "core", 0)
    assert {:ok, final} = PhaseRuns.get_or_create(final_phase, "core", 0)
    assert {:ok, _} = PhaseRuns.link_gust_run(pilot, 721)

    assert {:error,
            %StudyError{
              code: "conflict",
              issues: [%{"code" => "final_phase_run_conflict"}]
            }} = PhaseRuns.link_gust_run(final, 721)

    assert %StudyPhaseRun{gust_run_id: nil} = Repo.get!(StudyPhaseRun, final.id)
  end

  test "PHASE-RUN-09: WHEN a phase is deleted, THE database SHALL cascade-delete its runs",
       %{final_phase: phase} do
    assert {:ok, run} = PhaseRuns.get_or_create(phase, "core", 0)
    assert {:ok, _deleted} = Repo.delete(phase)
    assert Repo.get(StudyPhaseRun, run.id) == nil
    assert Repo.get(StudyPhase, phase.id) == nil
  end

  test "PHASE-RUN-10: WHEN invalid rows bypass changesets, THE database SHALL enforce phase-run constraints",
       %{final_phase: phase} do
    assert_db_violation(:foreign_key_violation, UUID.generate(), "core", 0)
    assert_db_violation(:check_violation, phase.id, "core", -1)

    assert {:ok, _} = PhaseRuns.get_or_create(phase, "core", 0)
    assert_db_violation(:unique_violation, phase.id, "edge", 0)
    assert_db_violation(:unique_violation, phase.id, "core", 1)
  end

  defp assert_db_violation(code, phase_id, tier, position) do
    assert {:error, %Postgrex.Error{postgres: %{code: ^code}}} =
             Repo.query(
               """
               INSERT INTO evaluation_study_phase_runs
                 (id, study_phase_id, tier, tier_position, inserted_at, updated_at)
               VALUES ($1, $2, $3, $4, now(), now())
               """,
               [UUID.dump!(UUID.generate()), UUID.dump!(phase_id), tier, position],
               mode: :savepoint
             )
  end
end
