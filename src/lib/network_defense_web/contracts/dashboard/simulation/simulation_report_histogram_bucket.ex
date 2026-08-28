defmodule NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportHistogramBucket do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :lower_bound, :integer
    field :upper_bound, :integer
    field :count, :integer
  end

  @type t :: %__MODULE__{lower_bound: integer(), upper_bound: integer(), count: integer()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:lower_bound, :upper_bound, :count])
    |> validate_required([:lower_bound, :upper_bound, :count])
  end
end
