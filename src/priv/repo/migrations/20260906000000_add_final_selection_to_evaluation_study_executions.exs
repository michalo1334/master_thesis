defmodule NetworkDefense.Repo.Migrations.AddFinalSelectionToEvaluationStudyExecutions do
  use Ecto.Migration

  def change do
    alter table(:evaluation_study_executions) do
      add :selected_candidate_id, :string
      add :selected_plan_count_per_side, :integer
      add :selected_attacks_per_plan, :integer
      add :pilot_override, :boolean
    end

    create constraint(
             :evaluation_study_executions,
             :evaluation_study_executions_final_selection_all_or_none,
             check: """
             (selected_candidate_id IS NULL AND
              selected_plan_count_per_side IS NULL AND
              selected_attacks_per_plan IS NULL AND
              pilot_override IS NULL)
             OR
             (selected_candidate_id IS NOT NULL AND
              selected_plan_count_per_side IS NOT NULL AND
              selected_attacks_per_plan IS NOT NULL AND
              pilot_override IS NOT NULL)
             """
           )

    create constraint(
             :evaluation_study_executions,
             :evaluation_study_executions_selected_candidate_id_valid,
             check:
               "selected_candidate_id IS NULL OR char_length(selected_candidate_id) BETWEEN 1 AND 128"
           )

    create constraint(
             :evaluation_study_executions,
             :evaluation_study_executions_selected_plan_count_positive,
             check: "selected_plan_count_per_side IS NULL OR selected_plan_count_per_side > 0"
           )

    create constraint(
             :evaluation_study_executions,
             :evaluation_study_executions_selected_attacks_per_plan_positive,
             check: "selected_attacks_per_plan IS NULL OR selected_attacks_per_plan > 0"
           )
  end
end
