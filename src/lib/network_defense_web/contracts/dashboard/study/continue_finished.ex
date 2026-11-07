defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.ContinueFinished do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :document_id, :string
    field :execution_id, :string
    field :request_id, :string
    embeds_one :status, NetworkDefenseWeb.Contracts.Dashboard.Study.Status, on_replace: :delete
    embeds_one :error, NetworkDefenseWeb.Contracts.Dashboard.Study.Error, on_replace: :delete
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          execution_id: String.t(),
          request_id: String.t(),
          status: NetworkDefenseWeb.Contracts.Dashboard.Study.Status.t() | nil,
          error: NetworkDefenseWeb.Contracts.Dashboard.Study.Error.t() | nil
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
