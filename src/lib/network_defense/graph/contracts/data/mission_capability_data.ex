defmodule NetworkDefense.Graph.Contracts.Data.MissionCapabilityData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.Graph.Contracts.Data.RequiredServiceFlowData

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

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :description, :impact_weight, :min_operational_support])
    |> cast_embed(:required_flows)
    |> validate_required([:name, :impact_weight, :min_operational_support])
    |> validate_number(:impact_weight, greater_than: 0)
    |> validate_number(:min_operational_support, greater_than: 0)
  end
end
