defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.PilotComparison do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    embeds_one :identity, NetworkDefenseWeb.Contracts.Dashboard.Study.ComparisonIdentity,
      on_replace: :delete

    field :guarded_half_width, :float
    field :informative, :boolean
    field :passes, :boolean
  end

  @type t :: %__MODULE__{
          identity: NetworkDefenseWeb.Contracts.Dashboard.Study.ComparisonIdentity.t(),
          guarded_half_width: float() | nil,
          informative: boolean(),
          passes: boolean()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
