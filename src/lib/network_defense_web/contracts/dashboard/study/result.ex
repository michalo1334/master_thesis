defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Result do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :execution_id, :string

    embeds_one :revision, NetworkDefenseWeb.Contracts.Dashboard.Study.Revision,
      on_replace: :delete

    embeds_one :pilot_outcome, NetworkDefenseWeb.Contracts.Dashboard.Study.PilotOutcome,
      on_replace: :delete

    embeds_one :selection, NetworkDefenseWeb.Contracts.Dashboard.Study.Selection,
      on_replace: :delete

    field :family_id, :string
    field :family_method, :string
    field :family_alpha, :float

    embeds_many :comparisons, NetworkDefenseWeb.Contracts.Dashboard.Study.FinalComparison,
      on_replace: :delete

    embeds_many :timing, NetworkDefenseWeb.Contracts.Dashboard.Study.TimingTier,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          execution_id: String.t(),
          revision: NetworkDefenseWeb.Contracts.Dashboard.Study.Revision.t(),
          pilot_outcome: NetworkDefenseWeb.Contracts.Dashboard.Study.PilotOutcome.t(),
          selection: NetworkDefenseWeb.Contracts.Dashboard.Study.Selection.t(),
          family_id: String.t(),
          family_method: String.t(),
          family_alpha: float(),
          comparisons: [NetworkDefenseWeb.Contracts.Dashboard.Study.FinalComparison.t()],
          timing: [NetworkDefenseWeb.Contracts.Dashboard.Study.TimingTier.t()]
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
