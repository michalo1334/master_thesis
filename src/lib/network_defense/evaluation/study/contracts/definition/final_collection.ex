defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.FinalCollection do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.TierRoot

  # The declared Final seed roles.
  #
  # Final collection counts are not declared here. They follow the candidate
  # that the reviewed Pilot handoff resumes, so this block declares only the
  # ordered selection pool and the roots, one root per declared tier.
  #
  # The pool must cover the largest declared candidate, because any candidate
  # may be the resumed one. An unused seed is allowed.

  @type t :: %__MODULE__{
          selection_seeds: [non_neg_integer()],
          roots: [TierRoot.t()]
        }

  embedded_schema do
    field :selection_seeds, {:array, :integer}
    embeds_many :roots, TierRoot, on_replace: :delete
  end

  def changeset(collection, attrs) do
    collection
    |> change()
    |> cast(attrs, [:selection_seeds])
    |> cast_embed(:roots, required: true)
    |> validate_required([:selection_seeds])
    |> validate_length(:selection_seeds, min: 1)
  end
end
