defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ListStudyTierRunsPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  @enum_values mode: [:pilot, :final]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :specification_id, :string
    field :tier, :string
    field :mode, :string
  end

  @type t :: %__MODULE__{specification_id: String.t(), tier: String.t(), mode: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:specification_id, :tier, :mode])
    |> validate_required([:specification_id, :tier, :mode])
    |> validate_inclusion(:mode, ["pilot", "final"])
    |> validate_length(:tier, min: 1, max: 255)
    |> Contracts.validate_uuid(:specification_id)
  end
end
