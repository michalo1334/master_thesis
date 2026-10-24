defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.Pilot do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.{
    Candidate,
    PilotAnalysis,
    PilotCollection
  }

  # The Pilot candidate grid, its collection capacity, and its analysis settings.
  #
  # The candidate list is the declared search grid. The collection block states
  # the capacity that the grid needs and the seed roles that the collection
  # consumes. The analysis block states the precision settings and the base seed
  # of the historical comparison stream.

  @type t :: %__MODULE__{
          candidates: [Candidate.t()],
          collection: PilotCollection.t(),
          analysis: PilotAnalysis.t()
        }

  embedded_schema do
    embeds_many :candidates, Candidate, on_replace: :delete
    embeds_one :collection, PilotCollection, on_replace: :update
    embeds_one :analysis, PilotAnalysis, on_replace: :update
  end

  def changeset(pilot, attrs) do
    pilot
    |> change()
    |> cast(attrs, [])
    |> cast_embed(:candidates, required: true)
    |> cast_embed(:collection, required: true)
    |> cast_embed(:analysis, required: true)
    |> validate_length(:candidates, min: 1)
  end
end
