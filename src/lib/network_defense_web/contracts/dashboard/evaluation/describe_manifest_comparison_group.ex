defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.DescribeManifestComparisonGroup do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.DescribeManifestPlanGroup

  embedded_schema do
    field :index, :integer
    embeds_one :tested, DescribeManifestPlanGroup, on_replace: :update
    embeds_one :baseline, DescribeManifestPlanGroup, on_replace: :update
    field :outcome, :string
  end

  @type t :: %__MODULE__{
          index: integer(),
          tested: DescribeManifestPlanGroup.t() | nil,
          baseline: DescribeManifestPlanGroup.t() | nil,
          outcome: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:index, :outcome])
    |> cast_embed(:tested)
    |> cast_embed(:baseline)
    |> validate_required([:index, :tested, :baseline, :outcome])
  end
end
