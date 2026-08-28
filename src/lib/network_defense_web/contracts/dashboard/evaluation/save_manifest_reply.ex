defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.SaveManifestReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.{
    ManifestError,
    ManifestSummary
  }

  @enum_values status: [:ok, :invalid_manifest, :invalid_request]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    embeds_one :manifest, ManifestSummary, on_replace: :update
    embeds_many :errors, ManifestError, on_replace: :delete
  end

  @type t :: %__MODULE__{
          status: String.t(),
          manifest: ManifestSummary.t() | nil,
          errors: [ManifestError.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:manifest)
    |> cast_embed(:errors)
    |> validate_required(:status)
    |> validate_inclusion(:status, ["ok", "invalid_manifest", "invalid_request"])
  end
end
