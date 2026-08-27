defmodule NetworkDefense.Repo.Migrations.AddPurposeToEvaluationRuns do
  use Ecto.Migration

  def change do
    alter table(:evaluation_runs) do
      add :purpose, :string, null: false, default: "evaluation"
    end

    create constraint(:evaluation_runs, :evaluation_runs_purpose_check,
             check: "purpose IN ('evaluation', 'warmup')"
           )
  end
end
