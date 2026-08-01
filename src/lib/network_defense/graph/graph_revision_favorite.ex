defmodule NetworkDefense.Graph.GraphRevisionFavorite do
  use Ecto.Schema

  alias NetworkDefense.Graph.GraphRevision

  @primary_key false
  @foreign_key_type :binary_id

  schema "graph_revision_favorites" do
    belongs_to :graph_revision, GraphRevision, primary_key: true

    timestamps(type: :utc_datetime)
  end
end
