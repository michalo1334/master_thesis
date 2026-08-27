defmodule NetworkDefense.Repo.Migrations.AddRuntimeToEvaluationRuns do
  use Ecto.Migration

  def change do
    alter table(:evaluation_runs) do
      add :runtime_ms, :bigint
    end

    create constraint(:evaluation_runs, :evaluation_runs_runtime_ms_non_negative,
             check: "runtime_ms IS NULL OR runtime_ms >= 0"
           )
  end
end
