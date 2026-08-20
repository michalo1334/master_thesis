defmodule NetworkDefense.Evaluation.EvaluationRuns do
  @moduledoc """
  Persists `EvaluationRun` records.
  """

  import Ecto.Query

  alias NetworkDefense.Evaluation.EvaluationRun
  alias NetworkDefense.Repo

  def create(attrs) do
    %EvaluationRun{}
    |> EvaluationRun.changeset(attrs)
    |> Repo.insert()
  end

  def get(id), do: Repo.get(EvaluationRun, id)

  def get_with_manifest(id) do
    EvaluationRun
    |> where([run], run.id == ^id)
    |> preload(:evaluation_manifest)
    |> Repo.one()
  end

  def list_by_manifest(manifest_id) do
    EvaluationRun
    |> where([run], run.evaluation_manifest_id == ^manifest_id)
    |> order_by([run], desc: run.inserted_at)
    |> Repo.all()
  end

  def latest_for_manifest(manifest_id) do
    EvaluationRun
    |> where([run], run.evaluation_manifest_id == ^manifest_id)
    |> order_by([run], desc: run.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def complete(%EvaluationRun{} = run) do
    run
    |> EvaluationRun.changeset(%{status: "completed"})
    |> Repo.update()
  end

  def fail(%EvaluationRun{} = run, reason) do
    run
    |> EvaluationRun.changeset(%{status: "failed", failure_reason: reason})
    |> Repo.update()
  end
end
