defmodule NetworkDefense.Repo.Migrations.CreateWorkflowRuns do
  use Ecto.Migration

  def change do
    create table(:workflow_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :template, :string, null: false
      add :input, :map, null: false
      add :status, :string, null: false, default: "running"

      timestamps(type: :utc_datetime)
    end

    create table(:workflow_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workflow_run_id,
          references(:workflow_runs, type: :binary_id, on_delete: :delete_all),
          null: false

      add :position, :integer, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :resource_id, :string
      add :output, :map

      timestamps(type: :utc_datetime)
    end

    create index(:workflow_runs, [:template])
    create unique_index(:workflow_steps, [:workflow_run_id, :position])
    create unique_index(:workflow_steps, [:workflow_run_id, :name])
  end
end
