defmodule NetworkDefense.Evaluation.StudySpecifications do
  @moduledoc """
  Persists `StudySpecification` versions.

  Versions are immutable. Ordering is deterministic so the dashboard list and
  version history stay stable: newest version first.
  """

  import Ecto.Query

  alias NetworkDefense.Evaluation.StudySpecification
  alias NetworkDefense.Repo

  @spec insert(map()) :: {:ok, StudySpecification.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs) do
    %StudySpecification{}
    |> StudySpecification.changeset(attrs)
    |> Repo.insert()
  end

  @spec list() :: [StudySpecification.t()]
  def list do
    StudySpecification
    |> order_by([specification],
      asc: specification.study_id,
      desc: specification.specification_version
    )
    |> Repo.all()
  end

  @spec list_versions(String.t()) :: [StudySpecification.t()]
  def list_versions(study_id) do
    StudySpecification
    |> where([specification], specification.study_id == ^study_id)
    |> order_by([specification], desc: specification.specification_version)
    |> Repo.all()
  end

  @spec get(String.t()) :: StudySpecification.t() | nil
  def get(id), do: Repo.get(StudySpecification, id)

  @spec get_version(String.t(), pos_integer()) :: StudySpecification.t() | nil
  def get_version(study_id, specification_version) do
    Repo.get_by(StudySpecification,
      study_id: study_id,
      specification_version: specification_version
    )
  end
end
