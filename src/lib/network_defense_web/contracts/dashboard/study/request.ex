defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Request do
  @moduledoc false
  use NetworkDefenseWeb.StudyContract, enums: [:approval]

  embedded_schema do
    field :document_id, :string
    field :execution_id, :string

    embeds_one :revision, NetworkDefenseWeb.Contracts.Dashboard.Study.Revision,
      on_replace: :delete

    embeds_one :definition, NetworkDefenseWeb.Contracts.Dashboard.Study.DefinitionInput,
      on_replace: :delete

    field :query, :string
    field :limit, :integer
    field :offset, :integer
    field :watch_id, :string
    field :request_id, :string
    field :approval, :string
    field :candidate_id, :string
    field :timeout_ms, :integer
  end

  @type t :: %__MODULE__{
          document_id: String.t() | nil,
          execution_id: String.t() | nil,
          revision: NetworkDefenseWeb.Contracts.Dashboard.Study.Revision.t() | nil,
          definition: NetworkDefenseWeb.Contracts.Dashboard.Study.DefinitionInput.t() | nil,
          query: String.t() | nil,
          limit: non_neg_integer() | nil,
          offset: non_neg_integer() | nil,
          watch_id: String.t() | nil,
          request_id: String.t() | nil,
          approval: String.t() | nil,
          candidate_id: String.t() | nil,
          timeout_ms: non_neg_integer() | nil
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
