defmodule NetworkDefense.Graph.Contracts.Data.NetworkSegmentData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.Nodes.Validation

  embedded_schema do
    field :name, :string
    field :cidr, :string
  end

  @type t :: %__MODULE__{
          name: String.t(),
          cidr: String.t() | nil
        }

  def changeset(schema, attrs), do: Validation.network_segment_changeset(schema, attrs)
end
