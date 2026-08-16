defmodule NetworkDefense.Graph.GraphRevision do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Graph.Graph

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "graph_revisions" do
    belongs_to :graph, Graph
    belongs_to :parent_revision, __MODULE__
    has_many :child_revisions, __MODULE__, foreign_key: :parent_revision_id

    field :number, :integer
    field :kind, Ecto.Enum, values: [:initial, :edit, :optimization]
    field :title, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [:parent_revision_id, :number, :kind, :title])
    |> validate_required([:graph_id, :number, :kind, :title])
    |> validate_number(:number, greater_than: 0)
    |> validate_length(:title, min: 1, max: 255)
    |> foreign_key_constraint(:graph_id)
    |> foreign_key_constraint(:parent_revision_id,
      name: :graph_revisions_parent_revision_graph_fkey
    )
    |> unique_constraint([:graph_id, :number])
  end
end
