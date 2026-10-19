defmodule NetworkDefense.Evaluation.Pilot.Contracts.ComparisonEvidence do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Comparison.Contracts.Evidence
  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Pilot.Contracts.Provenance

  # One declared comparison inside a snapshot. Position fixes tier rank and
  # within-tier occurrence order. The accepted Stage 2 evidence contract owns
  # the matrix shape.

  @type t :: %__MODULE__{
          position: non_neg_integer(),
          identity: Identity.t(),
          evidence: struct(),
          provenance: Provenance.t()
        }

  embedded_schema do
    field :position, :integer
    embeds_one :identity, Identity, on_replace: :update
    embeds_one :evidence, Evidence, on_replace: :update
    embeds_one :provenance, Provenance, on_replace: :update
  end

  def changeset(comparison, attrs) do
    comparison
    |> cast(attrs, [:position])
    |> cast_embed(:identity, required: true)
    |> cast_embed(:evidence, required: true)
    |> cast_embed(:provenance, required: true)
  end
end
