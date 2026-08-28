defmodule NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportActionSuccess do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :action_type, :string
    field :attempts, :integer
    field :successes, :integer
  end

  @type t :: %__MODULE__{action_type: String.t(), attempts: integer(), successes: integer()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:action_type, :attempts, :successes])
    |> validate_required([:action_type, :attempts, :successes])
  end
end
