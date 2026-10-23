defmodule NetworkDefense.Graph.Contracts.Data.MissionCapabilityData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.Graph.Contracts.Data.RequiredServiceFlowData
  alias NetworkDefense.Graph.Data

  embedded_schema do
    field :name, :string
    field :description, :string
    field :impact_weight, :float
    field :min_operational_support, :integer
    embeds_many :required_flows, RequiredServiceFlowData, on_replace: :delete
  end

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          impact_weight: float(),
          min_operational_support: pos_integer(),
          required_flows: [RequiredServiceFlowData.t()]
        }

  def changeset(schema, attrs), do: Data.mission_capability_changeset(schema, attrs)
end
