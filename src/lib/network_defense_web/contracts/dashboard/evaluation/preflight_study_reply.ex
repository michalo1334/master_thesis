defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.PreflightStudyReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyRunError

  @enum_values status: [:ok, :rejected, :invalid_request]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    field :study_id, :string
    field :specification_version, :integer
    field :tier_count, :integer
    field :required_inputs, :string
    embeds_many :errors, StudyRunError, on_replace: :delete
  end

  @type t :: %__MODULE__{
          status: String.t(),
          study_id: String.t() | nil,
          specification_version: pos_integer() | nil,
          tier_count: non_neg_integer() | nil,
          required_inputs: String.t() | nil,
          errors: [StudyRunError.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status, :study_id, :specification_version, :tier_count, :required_inputs])
    |> cast_embed(:errors)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "rejected", "invalid_request"])
    |> validate_number(:specification_version, greater_than: 0)
    |> validate_number(:tier_count, greater_than_or_equal_to: 0)
  end
end
