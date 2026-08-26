defmodule NetworkDefenseWeb.Web.Contracts.DescribeManifestReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Web.Contracts.{
    DescribeManifestComparisonGroup,
    DescribeManifestPlan,
    ManifestError
  }

  @enum_values status: [:ok, :invalid_manifest, :invalid_request]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    embeds_many :plans, DescribeManifestPlan, on_replace: :delete
    embeds_many :comparison_groups, DescribeManifestComparisonGroup, on_replace: :delete
    embeds_many :errors, ManifestError, on_replace: :delete
  end

  @type t :: %__MODULE__{
          status: String.t(),
          plans: [DescribeManifestPlan.t()],
          comparison_groups: [DescribeManifestComparisonGroup.t()],
          errors: [ManifestError.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:plans)
    |> cast_embed(:comparison_groups)
    |> cast_embed(:errors)
    |> validate_required(:status)
    |> validate_inclusion(:status, ["ok", "invalid_manifest", "invalid_request"])
  end
end
