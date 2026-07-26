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
      :host_count
    ]

    schema
    |> cast(attrs, fields)
    |> validate_required(fields)
  end
end
