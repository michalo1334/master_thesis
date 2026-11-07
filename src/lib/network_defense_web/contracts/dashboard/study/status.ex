defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Status do
  @moduledoc false
  use NetworkDefenseWeb.StudyContract, enums: [:state]

  embedded_schema do
    field :execution_id, :string

    embeds_one :revision, NetworkDefenseWeb.Contracts.Dashboard.Study.Revision,
      on_replace: :delete

    field :state, :string

    embeds_one :pilot_outcome, NetworkDefenseWeb.Contracts.Dashboard.Study.PilotOutcome,
      on_replace: :delete

    embeds_one :selection, NetworkDefenseWeb.Contracts.Dashboard.Study.Selection,
      on_replace: :delete

    embeds_one :error, NetworkDefenseWeb.Contracts.Dashboard.Study.Error, on_replace: :delete
  end

  @type t :: %__MODULE__{
          execution_id: String.t(),
          revision: NetworkDefenseWeb.Contracts.Dashboard.Study.Revision.t(),
          state: String.t(),
          pilot_outcome: NetworkDefenseWeb.Contracts.Dashboard.Study.PilotOutcome.t() | nil,
          selection: NetworkDefenseWeb.Contracts.Dashboard.Study.Selection.t() | nil,
          error: NetworkDefenseWeb.Contracts.Dashboard.Study.Error.t() | nil
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
