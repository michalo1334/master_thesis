defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Progress do
  @moduledoc false
  use NetworkDefenseWeb.StudyContract, enums: [:phase, :tier]

  embedded_schema do
    field :execution_id, :string
    embeds_one :status, NetworkDefenseWeb.Contracts.Dashboard.Study.Status, on_replace: :delete
    field :phase, :string
    field :tier, :string
    field :replica, :integer
    field :warm_up, :boolean

    embeds_many :counters, NetworkDefenseWeb.Contracts.Dashboard.Study.Counter,
      on_replace: :delete

    field :activity, :string
  end

  @type t :: %__MODULE__{
          execution_id: String.t(),
          status: NetworkDefenseWeb.Contracts.Dashboard.Study.Status.t(),
          phase: String.t() | nil,
          tier: String.t() | nil,
          replica: integer() | nil,
          warm_up: boolean(),
          counters: [NetworkDefenseWeb.Contracts.Dashboard.Study.Counter.t()],
          activity: String.t() | nil
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
