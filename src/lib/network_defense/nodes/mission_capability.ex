defmodule NetworkDefense.Nodes.MissionCapability do
  use Ecto.Schema

  alias NetworkDefense.Graph.Data
  alias NetworkDefense.Nodes.RequiredServiceFlow

  @primary_key false

  embedded_schema do
    field :name, :string
    field :description, :string
    field :impact_weight, :float, default: 1.0
    field :min_operational_support, :integer, default: 1
    embeds_many :required_flows, RequiredServiceFlow, on_replace: :delete
  end

  def default_data do
    %{
      name: "New mission capability",
      impact_weight: 1.0,
      min_operational_support: 1,
      required_flows: []
    }
  end

  def changeset(schema, attrs), do: Data.mission_capability_changeset(schema, attrs)
end
