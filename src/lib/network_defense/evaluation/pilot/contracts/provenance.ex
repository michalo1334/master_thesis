defmodule NetworkDefense.Evaluation.Pilot.Contracts.Provenance do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # Immutable provenance of one comparison evidence matrix.

  @type t :: %__MODULE__{
          graph_revision_ids: [String.t()],
          model_revision: String.t(),
          collection_seed: non_neg_integer(),
          source_run_ids: [String.t()],
          environment: String.t()
        }

  embedded_schema do
    field :graph_revision_ids, {:array, :string}
    field :model_revision, :string
    field :collection_seed, :integer
    field :source_run_ids, {:array, :string}
    field :environment, :string
  end

  def changeset(provenance, attrs) do
    cast(provenance, attrs, [
      :graph_revision_ids,
      :model_revision,
      :collection_seed,
      :source_run_ids,
      :environment
    ])
  end
end
