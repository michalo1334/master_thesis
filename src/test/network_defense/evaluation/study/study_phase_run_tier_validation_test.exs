defmodule NetworkDefense.Evaluation.Study.StudyPhaseRunTierValidationTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.StudyPhaseRun

  @tag :unit
  test "PHASE-RUN-TIER-01: WHEN a stored tier is whitespace, THE changeset SHALL reject it" do
    for tier <- ["", "   ", "\t\n"] do
      run = %StudyPhaseRun{study_phase_id: Ecto.UUID.generate(), tier: tier, tier_position: 0}
      refute StudyPhaseRun.changeset(run, %{}).valid?

      refute StudyPhaseRun.changeset(%StudyPhaseRun{}, %{
               study_phase_id: run.study_phase_id,
               tier: tier,
               tier_position: 0
             }).valid?
    end
  end
end
