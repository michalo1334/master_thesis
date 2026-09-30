defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyAnalysisProgressEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  @phases [
    :building_bundle,
    :submitting_analysis,
    :waiting_for_service,
    :validating_result,
    :complete
  ]

  @enum_values mode: [:pilot, :final], phase: @phases

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :document_id, :string
    field :mode, :string
    field :attempt_id, :string
    field :phase, :string
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          mode: String.t(),
          attempt_id: String.t(),
          phase: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :mode, :attempt_id, :phase])
    |> validate_required([:document_id, :mode, :attempt_id, :phase])
    |> validate_inclusion(:mode, ["pilot", "final"])
    |> validate_inclusion(:phase, Enum.map(@phases, &Atom.to_string/1))
    |> Contracts.validate_uuid(:document_id)
  end
end
