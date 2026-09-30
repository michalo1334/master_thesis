defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ListStudyTierRunsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyTierRunSummary

  embedded_schema do
    field :required_inputs, :string
    embeds_many :runs, StudyTierRunSummary, on_replace: :delete
  end

  @type t :: %__MODULE__{
          required_inputs: String.t() | nil,
          runs: [StudyTierRunSummary.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:required_inputs])
    |> cast_embed(:runs)
  end
end
