defmodule NetworkDefenseWeb.Web.Contracts.ReportCharts do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :dashboard

  embedded_schema do
    embeds_many :blast_radius_distribution, NetworkDefenseWeb.Web.Contracts.ChartSpec,
      on_replace: :delete

    embeds_many :convergence, NetworkDefenseWeb.Web.Contracts.ChartSpec, on_replace: :delete
    embeds_many :action_stats, NetworkDefenseWeb.Web.Contracts.ChartSpec, on_replace: :delete
  end

  @type t :: %__MODULE__{
          blast_radius_distribution: [NetworkDefenseWeb.Web.Contracts.ChartSpec.t()],
          convergence: [NetworkDefenseWeb.Web.Contracts.ChartSpec.t()],
          action_stats: [NetworkDefenseWeb.Web.Contracts.ChartSpec.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:blast_radius_distribution)
    |> cast_embed(:convergence)
    |> cast_embed(:action_stats)
  end
end
