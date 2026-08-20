defmodule NetworkDefense.Evaluation.EvaluationManifest do
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Evaluation.EvaluationRun

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          manifest_id: String.t() | nil,
          title: String.t() | nil,
          content: map() | nil,
          runs: list(EvaluationRun.t()) | Ecto.Association.NotLoaded.t()
        }

  schema "evaluation_manifests" do
    field :manifest_id, :string
    field :title, :string
    field :content, :map

    has_many :runs, EvaluationRun, foreign_key: :evaluation_manifest_id

    timestamps(type: :utc_datetime)
  end

  def changeset(manifest, attrs) do
    manifest
    |> cast(attrs, [:manifest_id, :title, :content])
    |> validate_required([:manifest_id, :title, :content])
    |> validate_length(:manifest_id, min: 1, max: 255)
    |> validate_length(:title, min: 1, max: 255)
    |> unique_constraint(:manifest_id)
  end
end
