defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.SaveStudySpecificationReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ManifestError
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudySpecificationSummary

  @enum_values status: [:ok, :invalid_specification, :immutable_conflict, :invalid_request]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    embeds_one :specification, StudySpecificationSummary, on_replace: :update
    embeds_many :errors, ManifestError, on_replace: :delete
  end

  @type t :: %__MODULE__{
          status: String.t(),
          specification: StudySpecificationSummary.t() | nil,
          errors: [ManifestError.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:specification)
    |> cast_embed(:errors)
    |> validate_required(:status)
    |> validate_inclusion(:status, [
      "ok",
      "invalid_specification",
      "immutable_conflict",
      "invalid_request"
    ])
  end
end
