defmodule NetworkDefense.Repo.Migrations.PersistSharedEffectSettings do
  use Ecto.Migration

  # Fresh setup must provide the columns used by the existing effect owners.
  # Leave historical rows unchanged; their omitted settings are unknown.
  def change do
    alter table(:optimization_runs) do
      add :execution_config, :map
    end

    alter table(:experiments) do
      add :rules, {:array, :string}
      add :require_pre_attack_feasibility, :boolean
    end
  end
end
