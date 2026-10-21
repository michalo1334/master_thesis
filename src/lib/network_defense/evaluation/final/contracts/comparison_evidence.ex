defmodule NetworkDefense.Evaluation.Final.Contracts.ComparisonEvidence do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Comparison.Contracts.Evidence
  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Pilot.Contracts.Provenance

  # One declared Final comparison inside a Final evidence snapshot.
  #
  # Position fixes the declared order. The accepted Stage 2 evidence contract
  # owns the crossed matrix shape: independent plan rows on each side and one
  # shared ordered attack column list. Provenance is caller-asserted.

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
