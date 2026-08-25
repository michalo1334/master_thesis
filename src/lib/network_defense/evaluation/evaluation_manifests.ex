defmodule NetworkDefense.Evaluation.EvaluationManifests do
  @moduledoc """
  Persists `EvaluationManifest` records.
  """

  import Ecto.Query

  alias NetworkDefense.Evaluation.EvaluationManifest
  alias NetworkDefense.Repo

  def create(attrs) do
    %EvaluationManifest{}
    |> EvaluationManifest.changeset(attrs)
    |> Repo.insert()
  end

  def update_manifest(%EvaluationManifest{} = manifest, attrs) do
    manifest
    |> EvaluationManifest.changeset(attrs)
    |> Repo.update()
  end

  def list do
    EvaluationManifest
    |> order_by([manifest], asc: manifest.title)
    |> Repo.all()
  end

  def get(id), do: Repo.get(EvaluationManifest, id)

  def get_by_manifest_id(manifest_id),
    do: Repo.get_by(EvaluationManifest, manifest_id: manifest_id)
end
