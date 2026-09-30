defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.DescribeStudySpecificationReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ManifestError
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudySpecificationDescription

  @enum_values status: [:ok, :invalid_specification, :invalid_request]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    embeds_one :description, StudySpecificationDescription, on_replace: :update
    embeds_many :errors, ManifestError, on_replace: :delete
  end

  @type t :: %__MODULE__{
          status: String.t(),
          description: StudySpecificationDescription.t() | nil,
          errors: [ManifestError.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:description)
    |> cast_embed(:errors)
    |> validate_required(:status)
    |> validate_inclusion(:status, ["ok", "invalid_specification", "invalid_request"])
  end
end
