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

  def complete(%EvaluationRun{} = run, runtime_ms) do
    Repo.transaction(fn ->
      run = Repo.one(from(r in EvaluationRun, where: r.id == ^run.id, lock: "FOR UPDATE"))

      case run do
        %EvaluationRun{status: "running"} = run ->
          run
          |> EvaluationRun.changeset(%{status: "completed", runtime_ms: runtime_ms})
          |> Repo.update!()

        %EvaluationRun{} ->
          Repo.rollback(:not_running)

        nil ->
          Repo.rollback(:not_found)
      end
    end)
  end

  def fail(%EvaluationRun{} = run, reason) do
    Repo.transaction(fn ->
      locked = Repo.one(from(r in EvaluationRun, where: r.id == ^run.id, lock: "FOR UPDATE"))

      case locked do
        %EvaluationRun{status: "running"} = locked ->
          locked
          |> EvaluationRun.changeset(%{status: "failed", failure_reason: reason})
          |> Repo.update!()

        %EvaluationRun{} ->
          Repo.rollback(:not_running)

        nil ->
          Repo.rollback(:not_found)
      end
    end)
  end

  def cancel(run_id) do
    Repo.transaction(fn ->
      run = Repo.one(from(r in EvaluationRun, where: r.id == ^run_id, lock: "FOR UPDATE"))

      case run do
        %EvaluationRun{status: "running"} = run ->
          run
          |> EvaluationRun.changeset(%{status: "cancelled"})
          |> Repo.update!()

        %EvaluationRun{} ->
          Repo.rollback(:not_running)

        nil ->
          Repo.rollback(:not_found)
      end
    end)
  end
end
