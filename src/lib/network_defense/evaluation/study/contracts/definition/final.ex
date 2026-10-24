defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.Final do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.{FinalAnalysis, FinalCollection}

  # The Final phase settings.
  #
  # The plan count, the attack count, and the analysis comparison seeds are not
  # derived here. The counts follow the candidate that the reviewed Pilot
  # handoff resumes, so the definition declares only the seed roles and the
  # analysis controls.

  @type t :: %__MODULE__{
          collection: FinalCollection.t(),
          analysis: FinalAnalysis.t()
        }

  embedded_schema do
    embeds_one :collection, FinalCollection, on_replace: :update
    embeds_one :analysis, FinalAnalysis, on_replace: :update
  end

  def changeset(final, attrs) do
    final
    |> change()
    |> cast(attrs, [])
    |> cast_embed(:collection, required: true)
    |> cast_embed(:analysis, required: true)
  end
end
