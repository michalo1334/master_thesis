defmodule NetworkDefense.Repo.Migrations.AddTitleToWorkflowRuns do
  use Ecto.Migration

  import Ecto.Query

  alias NetworkDefense.Repo
  alias NetworkDefense.Workflows.AnalysisTitle

  def up do
    alter table(:workflow_runs) do
      add :title, :string
    end

    flush()

    from(run in "workflow_runs", where: is_nil(run.title), select: run.id)
    |> Repo.all()
    |> Enum.each(fn id ->
      from(run in "workflow_runs", where: run.id == ^id)
      |> Repo.update_all(set: [title: AnalysisTitle.from_id(id)])
    end)

    alter table(:workflow_runs) do
      modify :title, :string, null: false
    end
  end

  def down do
    alter table(:workflow_runs) do
      remove :title
    end
  end
end
