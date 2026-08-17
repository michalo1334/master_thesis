defmodule NetworkDefense.Nodes.RequiredServiceFlow do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :source_segment_id, :string
    field :target_service_id, :string
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:source_segment_id, :target_service_id])
    |> validate_required([:source_segment_id, :target_service_id])
  end
end
