defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.RevisionDetail do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    embeds_one :revision, NetworkDefenseWeb.Contracts.Dashboard.Study.Revision,
      on_replace: :delete

    embeds_one :authored, NetworkDefenseWeb.Contracts.Dashboard.Study.Definition,
      on_replace: :delete

    embeds_one :context, NetworkDefenseWeb.Contracts.Dashboard.Study.RevisionContext,
      on_replace: :delete

    embeds_one :structure, NetworkDefenseWeb.Contracts.Dashboard.Study.DefinitionStructure,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          revision: NetworkDefenseWeb.Contracts.Dashboard.Study.Revision.t(),
          authored: NetworkDefenseWeb.Contracts.Dashboard.Study.Definition.t(),
          context: NetworkDefenseWeb.Contracts.Dashboard.Study.RevisionContext.t(),
          structure: NetworkDefenseWeb.Contracts.Dashboard.Study.DefinitionStructure.t()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
