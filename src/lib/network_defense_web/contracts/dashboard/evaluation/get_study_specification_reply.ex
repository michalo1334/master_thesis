defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.GetStudySpecificationReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudySpecificationSummary

  embedded_schema do
    embeds_one :specification, StudySpecificationSummary, on_replace: :update
  end

  @type t :: %__MODULE__{specification: StudySpecificationSummary.t() | nil}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:specification)
  end
end
