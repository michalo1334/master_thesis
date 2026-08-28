defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StartEvaluationReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ManifestError

  @enum_values status: [:accepted, :rejected, :not_found]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    field :run_id, :string
    embeds_many :errors, ManifestError, on_replace: :delete
  end

  @type t :: %__MODULE__{
          status: String.t(),
          run_id: String.t() | nil,
          errors: [ManifestError.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status, :run_id])
    |> cast_embed(:errors)
    |> validate_required(:status)
    |> validate_inclusion(:status, ["accepted", "rejected", "not_found"])
  end
end
