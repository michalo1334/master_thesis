defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.RevisionSummary do
  @moduledoc false
  use NetworkDefenseWeb.StudyContract, enums: [latest_state: :state]

  embedded_schema do
    embeds_one :revision, NetworkDefenseWeb.Contracts.Dashboard.Study.Revision,
      on_replace: :delete

    field :name, :string
    field :created_at, :string
    field :execution_count, :integer
    field :latest_state, :string
  end

  @type t :: %__MODULE__{
          revision: NetworkDefenseWeb.Contracts.Dashboard.Study.Revision.t(),
          name: String.t() | nil,
          created_at: String.t(),
          execution_count: non_neg_integer(),
          latest_state: String.t() | nil
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
