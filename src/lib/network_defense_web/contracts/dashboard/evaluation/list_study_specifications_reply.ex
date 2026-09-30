defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ListStudySpecificationsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudySpecificationSummary

  embedded_schema do
    embeds_many :specifications, StudySpecificationSummary, on_replace: :delete
  end

  @type t :: %__MODULE__{specifications: [StudySpecificationSummary.t()]}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:specifications)
  end
end
