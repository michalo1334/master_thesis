defmodule NetworkDefense.Evaluation.Study.Revisions do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.Yaml
  alias NetworkDefense.Evaluation.StudyRevision
  alias NetworkDefense.Graph.GraphRevision
  alias NetworkDefense.Repo

  # Creation of one immutable study revision.
  #
  # The YAML boundary and the typed definition validate the whole document
  # first. Each declared graph revision is then resolved against its stored
  # record, and only then does one row join the database. A row holds the
  # normalized definition, never the source document.
  #
  # The declared study ID and revision number identify one caller revision and
  # are unique together. A duplicate declaration is a conflict: creation does
  # not compare content and does not return an existing row.

  @spec create(term()) :: {:ok, StudyRevision.t()} | {:error, StudyError.t()}
  def create(document) do
    with {:ok, value} <- Yaml.parse(document),
         {:ok, definition} <- Definition.parse(value),
         :ok <- resolve_graphs(definition) do
      insert(definition)
    end
  end

  defp resolve_graphs(%Definition{graphs: graphs}) do
    known =
      graphs
      |> Enum.map(& &1.graph_revision_id)
      |> then(&Repo.all(from revision in GraphRevision, where: revision.id in ^&1))
      |> MapSet.new(& &1.id)

    graphs
    |> Enum.with_index()
    |> Enum.find(fn {graph, _index} ->
      not MapSet.member?(known, graph.graph_revision_id)
    end)
    |> case do
      nil -> :ok
      {_graph, index} -> {:error, unresolved_graph(index)}
    end
  end

  defp unresolved_graph(index),
    do: StudyError.graph_revision_not_found(["graphs", index, "graph_revision_id"])

  defp insert(%Definition{} = definition) do
    attrs = %{
      study_id: definition.study.id,
      revision: definition.study.revision,
      schema_version: definition.schema_version,
      definition: Definition.to_params(definition)
    }

    case Repo.insert(StudyRevision.create_changeset(%StudyRevision{}, attrs)) do
      {:ok, revision} -> {:ok, revision}
      {:error, changeset} -> {:error, insert_error(changeset)}
    end
  end

  defp insert_error(changeset) do
    if Keyword.has_key?(changeset.errors, :study_id),
      do: StudyError.duplicate_revision(),
      else: StudyError.storage_failed()
  end
end
