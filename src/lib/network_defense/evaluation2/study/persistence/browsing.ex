defmodule NetworkDefense.Evaluation2.Study.Persistence.Browsing do
  @moduledoc """
  Bounded read-only listing of frozen revisions and their executions.

  The supported facade bounds every request before it reaches this module, so
  each query carries one limit and one offset. Both lists order by a total
  order: revisions by study identifier and descending revision number,
  executions by descending start time and descending identifier.

  A revision entry carries its execution count and the state of its most
  recently changed execution. The count comes from one grouped query, and the
  states come from one second query over the revisions of the page, so a page
  never reads execution rows one revision at a time.

  An execution entry reads the execution row only. Stored Pilot reports, Final
  results, timing and collection matrices belong to their own records and never
  enter a list read.
  """

  import Ecto.Query

  alias NetworkDefense.Evaluation2.Study.Lifecycle
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.{Execution, Revision}
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Repo

  @typedoc "Bounded revision list request."
  @type revision_request :: %{
          page: pos_integer(),
          page_size: pos_integer(),
          search: String.t() | nil
        }

  @typedoc "Bounded execution list request."
  @type execution_request :: %{page: pos_integer(), page_size: pos_integer()}

  @typedoc "One revision row with its execution count and latest state."
  @type revision_entry :: %{
          id: Ecto.UUID.t(),
          study_id: String.t(),
          name: String.t() | nil,
          revision: pos_integer(),
          inserted_at: DateTime.t(),
          execution_count: non_neg_integer(),
          latest_state: Lifecycle.state() | nil
        }

  @typedoc "One execution row with its decoded accepted context."
  @type execution_entry :: %{
          id: Ecto.UUID.t(),
          state: Lifecycle.state(),
          pilot_outcome: PilotOutcome.t() | nil,
          selection: Selection.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @typedoc "One bounded page of stored rows."
  @type page(entry) :: %{
          entries: [entry],
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer()
        }

  @typedoc "One bounded page of execution rows with the declared revision identity."
  @type execution_page :: %{
          entries: [execution_entry()],
          revision: %{study_id: String.t(), revision: pos_integer()},
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer()
        }

  @doc "List one bounded page of revisions, optionally filtered by study name or identifier."
  @spec list_revisions(revision_request()) :: Persistence.response(page(revision_entry()))
  def list_revisions(%{page: page, page_size: page_size} = request) do
    Persistence.read(:list_revisions, :revision, fn ->
      rows =
        request
        |> revision_query()
        |> limit(^page_size)
        |> offset(^page_offset(page, page_size))
        |> Repo.all()

      %{
        entries: with_latest_states(rows),
        page: page,
        page_size: page_size,
        total: revision_total(request)
      }
    end)
  end

  @doc """
  List one bounded page of executions of one declared revision.

  A missing revision reports the ordinary not-found failure, so an existing
  revision without executions reports an empty page instead.
  """
  @spec list_executions(Persistence.revision_ref(), execution_request()) ::
          Persistence.response(execution_page())
  def list_executions(revision_ref, %{page: page, page_size: page_size} = request) do
    with {:ok, identity} <- Persistence.cast_identity(revision_ref, :list_executions),
         {:ok, revision_id} <- revision_id(identity, :list_executions),
         {:ok, stored} <-
           Persistence.read(:list_executions, :execution, fn ->
             page_rows(revision_id, request)
           end),
         {:ok, entries} <- execution_entries(stored.entries) do
      {:ok,
       %{
         entries: entries,
         revision: identity,
         page: page,
         page_size: page_size,
         total: stored.total
       }}
    end
  end

  defp revision_id(identity, operation) do
    query =
      from r in Revision,
        where: r.study_id == ^identity.study_id and r.revision == ^identity.revision,
        select: r.id

    Persistence.fetch_one(operation, :revision, query, &{:ok, &1})
  end

  defp revision_query(request) do
    from(r in Revision,
      left_join: e in Execution,
      on: e.study_revision_id == r.id,
      group_by: r.id,
      order_by: [asc: r.study_id, desc: r.revision],
      select: %{
        id: r.id,
        study_id: r.study_id,
        name: fragment("?->'study'->>'name'", r.definition),
        revision: r.revision,
        inserted_at: r.inserted_at,
        execution_count: count(e.id)
      }
    )
    |> search_revisions(request.search)
  end

  defp search_revisions(query, nil), do: query

  defp search_revisions(query, search) do
    pattern = like_pattern(search)

    where(
      query,
      [r],
      ilike(r.study_id, ^pattern) or
        ilike(fragment("?->'study'->>'name'", r.definition), ^pattern)
    )
  end

  defp revision_total(request) do
    from(r in Revision, select: count(r.id))
    |> search_revisions(request.search)
    |> Repo.one()
  end

  # The state of the most recently changed execution describes the latest
  # activity of a revision, so browsing shows current attention rather than the
  # oldest attempt.
  defp with_latest_states(rows) do
    states = latest_states(Enum.map(rows, & &1.id))

    Enum.map(rows, fn row -> Map.put(row, :latest_state, Map.get(states, row.id)) end)
  end

  defp latest_states([]), do: %{}

  defp latest_states(revision_ids) do
    from(e in Execution,
      where: e.study_revision_id in ^revision_ids,
      distinct: e.study_revision_id,
      order_by: [asc: e.study_revision_id, desc: e.updated_at, desc: e.id],
      select: {e.study_revision_id, e.state}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp page_rows(revision_id, request) do
    rows =
      from(e in Execution,
        where: e.study_revision_id == ^revision_id,
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: ^request.page_size,
        offset: ^page_offset(request.page, request.page_size),
        select: %{
          id: e.id,
          state: e.state,
          pilot_outcome: e.pilot_outcome,
          selection: e.selection,
          inserted_at: e.inserted_at,
          updated_at: e.updated_at
        }
      )
      |> Repo.all()

    %{
      entries: rows,
      total:
        Repo.one(
          from e in Execution, where: e.study_revision_id == ^revision_id, select: count(e.id)
        )
    }
  end

  defp execution_entries(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, entries} ->
      with {:ok, pilot_outcome} <-
             Persistence.decode_optional_json(
               PilotOutcome,
               :t,
               row.pilot_outcome,
               :list_executions,
               :pilot_outcome
             ),
           {:ok, selection} <-
             Persistence.decode_optional_json(
               Selection,
               :t,
               row.selection,
               :list_executions,
               :selection
             ) do
        entry = %{row | pilot_outcome: pilot_outcome, selection: selection}
        {:cont, {:ok, [entry | entries]}}
      else
        {:error, failure} -> {:halt, {:error, failure}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, failure} -> {:error, failure}
    end
  end

  defp page_offset(page, page_size), do: (page - 1) * page_size

  # A study identifier is operator text, so search matches its literal characters
  # instead of reading LIKE wildcards.
  defp like_pattern(search) do
    escaped =
      search
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%" <> escaped <> "%"
  end
end
