defmodule NetworkDefense.Repo.Migrations.CreateOptimizationRuns do
  use Ecto.Migration

  def change do
    create table(:optimization_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :graph_revision_id,
          references(:graph_revisions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :output_graph_revision_id,
          references(:graph_revisions, type: :binary_id, on_delete: :delete_all)

      add :correlation_id, :string, null: false
      add :strategy, :string, null: false
      add :requested_budget, :integer, null: false
      add :used_budget, :integer, null: false, default: 0
      add :runtime_ms, :integer, null: false, default: 0
      add :status, :string, null: false, default: "running"
      add :error, :string

      timestamps(type: :utc_datetime)
    end

    create index(:optimization_runs, [:graph_revision_id])
    create index(:optimization_runs, [:correlation_id])

    create constraint(:optimization_runs, :optimization_runs_requested_budget_positive,
             check: "requested_budget > 0"
           )

    create constraint(:optimization_runs, :optimization_runs_used_budget_non_negative,
             check: "used_budget >= 0"
           )

    create constraint(:optimization_runs, :optimization_runs_runtime_ms_non_negative,
             check: "runtime_ms >= 0"
           )

    create table(:optimization_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :optimization_run_id,
          references(:optimization_runs, type: :binary_id, on_delete: :delete_all),
          null: false

      add :position, :integer, null: false
      add :action_type, :string, null: false
      add :target_type, :string, null: false
      add :target_id, :binary_id, null: false
      add :cost, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:optimization_actions, [:optimization_run_id])
    create unique_index(:optimization_actions, [:optimization_run_id, :position])

    create constraint(:optimization_actions, :optimization_actions_position_positive,
             check: "position > 0"
           )

    create constraint(:optimization_actions, :optimization_actions_cost_non_negative,
             check: "cost >= 0"
           )
  end
end
