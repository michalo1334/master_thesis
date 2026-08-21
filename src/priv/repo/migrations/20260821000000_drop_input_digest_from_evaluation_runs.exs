defmodule NetworkDefense.Repo.Migrations.DropInputDigestFromEvaluationRuns do
  use Ecto.Migration

  def change do
    alter table(:evaluation_runs) do
      remove :input_digest, :string
    end
  end
end
