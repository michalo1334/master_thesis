defmodule NetworkDefense.Repo.Migrations.UpdateWorkflowRunTitles do
  use Ecto.Migration

  import Ecto.Query

  alias NetworkDefense.Repo
  alias NetworkDefense.Workflows.AnalysisTitle

  def up do
    from(run in "workflow_runs", select: run.id)
    |> Repo.all()
    |> Enum.each(fn id ->
      from(run in "workflow_runs", where: run.id == ^id)
      |> Repo.update_all(set: [title: AnalysisTitle.from_id(id)])
    end)
  end

  def down, do: :ok
end
