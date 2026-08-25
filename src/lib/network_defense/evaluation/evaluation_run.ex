defmodule NetworkDefense.Evaluation.EvaluationRun do
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Evaluation.EvaluationManifest
  alias NetworkDefense.Graph.GraphRevision

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          evaluation_manifest_id: String.t() | nil,
          evaluation_manifest: EvaluationManifest.t() | Ecto.Association.NotLoaded.t() | nil,
          source_graph_revision_id: String.t() | nil,
          source_graph_revision: GraphRevision.t() | Ecto.Association.NotLoaded.t() | nil,
          resolved_manifest: map() | nil,
          status: String.t() | nil,
          failure_reason: String.t() | nil
        }

  schema "evaluation_runs" do
    belongs_to :evaluation_manifest, EvaluationManifest
    belongs_to :source_graph_revision, GraphRevision

    field :resolved_manifest, :map
    field :status, :string, default: "running"
    field :failure_reason, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :evaluation_manifest_id,
      :source_graph_revision_id,
      :resolved_manifest,
      :status,
      :failure_reason
    ])
    |> validate_required([
      :evaluation_manifest_id,
      :source_graph_revision_id,
      :resolved_manifest,
      :status
    ])
    |> validate_inclusion(:status, ["running", "completed", "failed", "cancelled"])
    |> foreign_key_constraint(:evaluation_manifest_id)
    |> foreign_key_constraint(:source_graph_revision_id)
  end
end
