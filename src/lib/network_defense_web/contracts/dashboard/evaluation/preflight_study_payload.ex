defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.PreflightStudyPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyTierSelection

  @enum_values mode: [:pilot, :final]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :specification_id, :string
    field :mode, :string
    embeds_many :tier_runs, StudyTierSelection, on_replace: :delete
  end

  @type t :: %__MODULE__{
          specification_id: String.t(),
          mode: String.t(),
          tier_runs: [StudyTierSelection.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:specification_id, :mode])
    |> cast_embed(:tier_runs)
    |> validate_required([:specification_id, :mode])
    |> require_tier_runs_key(attrs)
    |> validate_inclusion(:mode, ["pilot", "final"])
    |> Contracts.validate_uuid(:specification_id)
  end

  # An empty selection is a valid preflight request: the domain returns the
  # actionable `no_tiers` validation state when a saved version is selected.
  # A missing key is still a malformed wire payload.
  defp require_tier_runs_key(changeset, attrs) when is_map(attrs) do
    if Map.has_key?(attrs, "tier_runs") or Map.has_key?(attrs, :tier_runs) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :tier_runs, "can't be blank")
    end
  end
end
