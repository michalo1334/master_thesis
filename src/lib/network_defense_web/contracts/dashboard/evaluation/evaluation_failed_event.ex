defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationFailedEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.DashboardError

  embedded_schema do
    field :run_id, :string
    field :manifest_id, :string
    field :manifest_title, :string
    embeds_one :error, DashboardError
  end

  @type t :: %__MODULE__{
          run_id: String.t(),
          manifest_id: String.t(),
          manifest_title: String.t(),
          error: DashboardError.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:run_id, :manifest_id, :manifest_title])
    |> cast_embed(:error)
    |> validate_required([:run_id, :manifest_id, :manifest_title, :error])
    |> NetworkDefense.Contracts.validate_uuid(:run_id)
  end
end
