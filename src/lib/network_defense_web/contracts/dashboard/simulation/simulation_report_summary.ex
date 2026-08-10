defmodule NetworkDefenseWeb.Web.Contracts.SimulationReportSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :expected_blast_radius, :float
    field :median_blast_radius, :integer
    field :blast_radius_p95, :integer
    field :blast_radius_p99, :integer
    field :min_blast_radius, :integer
    field :max_blast_radius, :integer
    field :blast_radius_variance, :float
    field :expected_mission_impact, :float
    field :median_mission_impact, :float
    field :mission_impact_p95, :float
    field :mission_impact_p99, :float
    field :min_mission_impact, :float
    field :max_mission_impact, :float
    field :mission_impact_variance, :float
    field :host_count, :integer
  end

  @type t :: %__MODULE__{
          expected_blast_radius: float(),
          median_blast_radius: integer(),
          blast_radius_p95: integer(),
          blast_radius_p99: integer(),
          min_blast_radius: integer(),
          max_blast_radius: integer(),
          blast_radius_variance: float(),
          expected_mission_impact: float(),
          median_mission_impact: float(),
          mission_impact_p95: float(),
          mission_impact_p99: float(),
          min_mission_impact: float(),
          max_mission_impact: float(),
          mission_impact_variance: float(),
          host_count: integer()
        }

  def changeset(schema, attrs) do
    fields = [
      :expected_blast_radius,
      :median_blast_radius,
      :blast_radius_p95,
      :blast_radius_p99,
      :min_blast_radius,
      :max_blast_radius,
      :blast_radius_variance,
      :expected_mission_impact,
      :median_mission_impact,
      :mission_impact_p95,
      :mission_impact_p99,
      :min_mission_impact,
      :max_mission_impact,
      :mission_impact_variance,
      :host_count
    ]

    schema
    |> cast(attrs, fields)
    |> validate_required(fields)
  end
end
