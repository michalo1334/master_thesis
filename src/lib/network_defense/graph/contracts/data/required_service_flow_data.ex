defmodule NetworkDefense.Graph.Contracts.Data.RequiredServiceFlowData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  embedded_schema do
    field :source_segment_id, :string
    field :target_service_id, :string
  end

  @type t :: %__MODULE__{
          source_segment_id: String.t(),
          target_service_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:source_segment_id, :target_service_id])
    |> validate_required([:source_segment_id, :target_service_id])
    |> Contracts.validate_uuid(:source_segment_id)
    |> Contracts.validate_uuid(:target_service_id)
  end
end
