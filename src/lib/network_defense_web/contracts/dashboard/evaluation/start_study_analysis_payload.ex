defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StartStudyAnalysisPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyTierSelection

  @enum_values mode: [:pilot, :final]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :document_id, :string
    field :specification_id, :string
    field :mode, :string
    embeds_many :tier_runs, StudyTierSelection, on_replace: :delete
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          specification_id: String.t() | nil,
          mode: String.t(),
          tier_runs: [StudyTierSelection.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :specification_id, :mode])
    |> cast_embed(:tier_runs)
    |> validate_required([:document_id, :mode])
    |> validate_inclusion(:mode, ["pilot", "final"])
    |> Contracts.validate_uuid(:specification_id)
    |> Contracts.validate_uuid(:document_id)
  end
end
