defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Error do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :category, :string
    embeds_many :issues, NetworkDefenseWeb.Contracts.Dashboard.Study.Issue, on_replace: :delete
  end

  @type t :: %__MODULE__{
          category: String.t(),
          issues: [NetworkDefenseWeb.Contracts.Dashboard.Study.Issue.t()]
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
