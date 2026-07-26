defmodule NetworkDefenseWeb.Web.Contracts.SimulationReportConvergencePoint do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :run, :integer
    field :mean_blast_radius, :float
  end

  @type t :: %__MODULE__{run: integer(), mean_blast_radius: float()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:run, :mean_blast_radius])
    |> validate_required([:run, :mean_blast_radius])
  end
end
