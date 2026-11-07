defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Reply do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :status, :string
    embeds_one :error, NetworkDefenseWeb.Contracts.Dashboard.Study.Error, on_replace: :delete

    embeds_one :revision, NetworkDefenseWeb.Contracts.Dashboard.Study.Revision,
      on_replace: :delete

    embeds_one :detail, NetworkDefenseWeb.Contracts.Dashboard.Study.RevisionDetail,
      on_replace: :delete

    embeds_one :options, NetworkDefenseWeb.Contracts.Dashboard.Study.DefinitionOptions,
      on_replace: :delete

    embeds_many :revisions, NetworkDefenseWeb.Contracts.Dashboard.Study.RevisionSummary,
      on_replace: :delete

    embeds_many :executions, NetworkDefenseWeb.Contracts.Dashboard.Study.ExecutionSummary,
      on_replace: :delete

    field :total, :integer
    embeds_one :execution, NetworkDefenseWeb.Contracts.Dashboard.Study.Status, on_replace: :delete

    embeds_one :progress, NetworkDefenseWeb.Contracts.Dashboard.Study.Progress,
      on_replace: :delete

    embeds_one :pilot, NetworkDefenseWeb.Contracts.Dashboard.Study.PilotResult,
      on_replace: :delete

    embeds_one :result, NetworkDefenseWeb.Contracts.Dashboard.Study.Result, on_replace: :delete
    field :request_id, :string
    field :watch_id, :string
  end

  @type t :: %__MODULE__{
          status: String.t(),
          error: NetworkDefenseWeb.Contracts.Dashboard.Study.Error.t() | nil,
          revision: NetworkDefenseWeb.Contracts.Dashboard.Study.Revision.t() | nil,
          detail: NetworkDefenseWeb.Contracts.Dashboard.Study.RevisionDetail.t() | nil,
          options: NetworkDefenseWeb.Contracts.Dashboard.Study.DefinitionOptions.t() | nil,
          revisions: [NetworkDefenseWeb.Contracts.Dashboard.Study.RevisionSummary.t()],
          executions: [NetworkDefenseWeb.Contracts.Dashboard.Study.ExecutionSummary.t()],
          total: non_neg_integer() | nil,
          execution: NetworkDefenseWeb.Contracts.Dashboard.Study.Status.t() | nil,
          progress: NetworkDefenseWeb.Contracts.Dashboard.Study.Progress.t() | nil,
          pilot: NetworkDefenseWeb.Contracts.Dashboard.Study.PilotResult.t() | nil,
          result: NetworkDefenseWeb.Contracts.Dashboard.Study.Result.t() | nil,
          request_id: String.t() | nil,
          watch_id: String.t() | nil
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
