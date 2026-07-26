defmodule NetworkDefenseWeb.Web.Contracts.SimulationReportCdfPoint do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :compromised_hosts, :integer
    field :cumulative_probability, :float
  end

  @type t :: %__MODULE__{compromised_hosts: integer(), cumulative_probability: float()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:compromised_hosts, :cumulative_probability])
    |> validate_required([:compromised_hosts, :cumulative_probability])
  end
end
