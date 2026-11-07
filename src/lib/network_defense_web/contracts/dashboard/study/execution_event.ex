defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.ExecutionEvent do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :document_id, :string
    field :execution_id, :string
    field :watch_id, :string
    field :sequence, :integer
    embeds_one :status, NetworkDefenseWeb.Contracts.Dashboard.Study.Status, on_replace: :delete

    embeds_one :progress, NetworkDefenseWeb.Contracts.Dashboard.Study.Progress,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          execution_id: String.t(),
          watch_id: String.t(),
          sequence: non_neg_integer(),
          status: NetworkDefenseWeb.Contracts.Dashboard.Study.Status.t(),
          progress: NetworkDefenseWeb.Contracts.Dashboard.Study.Progress.t()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
