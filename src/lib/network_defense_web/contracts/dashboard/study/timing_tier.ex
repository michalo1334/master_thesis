defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.TimingTier do
  @moduledoc false
  use NetworkDefenseWeb.StudyContract, enums: [:tier]

  embedded_schema do
    field :tier, :string

    embeds_many :replicas, NetworkDefenseWeb.Contracts.Dashboard.Study.TimingReplica,
      on_replace: :delete

    embeds_many :summaries, NetworkDefenseWeb.Contracts.Dashboard.Study.TimingSummary,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          tier: String.t(),
          replicas: [NetworkDefenseWeb.Contracts.Dashboard.Study.TimingReplica.t()],
          summaries: [NetworkDefenseWeb.Contracts.Dashboard.Study.TimingSummary.t()]
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
