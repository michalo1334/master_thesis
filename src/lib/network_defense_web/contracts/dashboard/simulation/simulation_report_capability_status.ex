defmodule NetworkDefenseWeb.Web.Contracts.SimulationReportCapabilityStatus do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :capability_id, :string
    field :operational, :boolean
    field :required_flow_count, :integer
    field :missing_flow_count, :integer
    field :supporting_host_count, :integer
    field :min_operational_support, :integer
  end

  @type t :: %__MODULE__{
          capability_id: String.t(),
          operational: boolean(),
          required_flow_count: integer(),
          missing_flow_count: integer(),
          supporting_host_count: integer(),
          min_operational_support: integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :capability_id,
      :operational,
      :required_flow_count,
      :missing_flow_count,
      :supporting_host_count,
      :min_operational_support
    ])
    |> validate_required([
      :capability_id,
      :operational,
      :required_flow_count,
      :missing_flow_count,
      :supporting_host_count,
      :min_operational_support
    ])
  end
end
