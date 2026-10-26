defmodule NetworkDefense.Evaluation.Study.FinalSelectionTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.Candidate
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.FinalSelection
  alias NetworkDefense.Evaluation.StudyExecution

  test "FINAL-SELECTION-01: WHEN a resolved candidate and stored execution are valid, THE selection SHALL materialize and map to only the execution selection columns" do
    candidate = %Candidate{
      id: "small",
      plan_count_per_side: 5,
      attacks_per_plan: 10
    }

    assert {:ok, %FinalSelection{} = selection} =
             FinalSelection.from_candidate(candidate, false)

    assert selection == %FinalSelection{
             candidate_id: "small",
             plan_count_per_side: 5,
             attacks_per_plan: 10,
             pilot_override: false
           }

    assert FinalSelection.to_execution_attrs(selection) == %{
             selected_candidate_id: "small",
             selected_plan_count_per_side: 5,
             selected_attacks_per_plan: 10,
             pilot_override: false
           }

    execution = %StudyExecution{
      selected_candidate_id: "small",
      selected_plan_count_per_side: 5,
      selected_attacks_per_plan: 10,
      pilot_override: false
    }

    assert {:ok, ^selection} = FinalSelection.from_execution(execution)
  end

  test "FINAL-SELECTION-02: WHEN stored selection fields are missing or invalid, THE parser SHALL reject the grouped selection with one bounded error" do
    invalid_selections = [
      %{selected_candidate_id: nil},
      %{selected_candidate_id: ""},
      %{selected_plan_count_per_side: 0},
      %{selected_attacks_per_plan: -1},
      %{pilot_override: nil}
    ]

    complete = %StudyExecution{
      selected_candidate_id: "small",
      selected_plan_count_per_side: 5,
      selected_attacks_per_plan: 10,
      pilot_override: false
    }

    expected_error = StudyError.pilot_source_incomplete()

    for invalid <- invalid_selections do
      execution = struct!(complete, invalid)
      assert {:error, ^expected_error} = FinalSelection.from_execution(execution)
    end
  end

  test "FINAL-SELECTION-03: WHEN changeset input contains an unknown field, THE changeset SHALL reject it and SHALL not preserve it" do
    changeset =
      FinalSelection.changeset(%FinalSelection{}, %{
        "candidate_id" => "small",
        "plan_count_per_side" => 5,
        "attacks_per_plan" => 10,
        "pilot_override" => false,
        "unknown" => "not-preserved"
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :base)
    refute Map.has_key?(changeset.changes, :unknown)
  end
end
