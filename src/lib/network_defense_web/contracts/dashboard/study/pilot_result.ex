defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.PilotResult do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :method, :string
    field :selection_rule, :string

    embeds_one :outcome, NetworkDefenseWeb.Contracts.Dashboard.Study.PilotOutcome,
      on_replace: :delete

    embeds_many :candidates, NetworkDefenseWeb.Contracts.Dashboard.Study.PilotCandidate,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          method: String.t(),
          selection_rule: String.t(),
          outcome: NetworkDefenseWeb.Contracts.Dashboard.Study.PilotOutcome.t(),
          candidates: [NetworkDefenseWeb.Contracts.Dashboard.Study.PilotCandidate.t()]
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
