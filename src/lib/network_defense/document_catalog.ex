defmodule NetworkDefense.DocumentCatalog do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Graph.{Graph, GraphRevision}
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Workflows.{AnalysisInputRevision, WorkflowRun}

  defmacrop analysis_ids(analysis_id, input_analysis_ids) do
    quote do
      type(
        fragment(
          "array_remove(ARRAY(SELECT DISTINCT unnest(array_append(COALESCE(?, ARRAY[]::uuid[]), ?))), NULL)",
          unquote(input_analysis_ids),
          unquote(analysis_id)
        ),
        {:array, :binary_id}
      )
    end
  end

  defmacrop analysis_ids(analysis_id) do
    quote do
      type(fragment("array_remove(ARRAY[?], NULL)", unquote(analysis_id)), {:array, :binary_id})
    end
  end

  @spec document_catalog(map()) :: map()
  def document_catalog(filters) do
    catalog = catalog_query()
    filtered = filter_catalog(catalog, filters)

    filter_options = filter_options(catalog)
    titles = Map.new(filter_options.analyses, &{&1.id, &1.title})

    items =
      filtered
      |> order_by([item], desc: item.created_at, desc: item.id)
      |> limit(^filters.limit)
      |> offset(^filters.offset)
      |> Repo.all()
      |> Enum.map(fn item ->
        item
        |> Map.update!(:created_at, &DateTime.to_iso8601/1)
        |> with_analyses(titles)
      end)

    %{
      items: items,
      total_count: filtered |> select([item], count(item.id)) |> Repo.one(),
      filter_options: filter_options
    }
  end

  defp catalog_query do
    input_analysis_ids = input_analysis_ids_query()

    graph_items(input_analysis_ids)
    |> union_all(^experiment_items())
    |> union_all(^optimization_items())
    |> subquery()
    |> then(&from(item in &1))
  end

  defp input_analysis_ids_query do
    from input in AnalysisInputRevision,
      group_by: input.graph_revision_id,
      select: %{
        graph_revision_id: input.graph_revision_id,
        analysis_ids: fragment("array_agg(DISTINCT ?)", input.workflow_run_id)
      }
  end

  defp graph_items(input_analysis_ids) do
    from revision in GraphRevision,
      join: graph in Graph,
      on: graph.id == revision.graph_id,
      left_join: input in subquery(input_analysis_ids),
      on: input.graph_revision_id == revision.id,
      select: %{
        id: revision.id,
        kind: "graph",
        graph_id: revision.graph_id,
        graph_revision_id: revision.id,
        graph_title: revision.title,
        analysis_ids: analysis_ids(revision.analysis_id, input.analysis_ids),
        revision_kind: type(revision.kind, :string),
        revision_number: revision.number,
        strategy: nil,
        output_graph_revision_id: type(fragment("NULL"), :binary_id),
        output_revision_kind: type(fragment("NULL"), :string),
        output_revision_number: type(fragment("NULL"), :integer),
        created_at: revision.inserted_at
      }
  end

  defp experiment_items do
    from experiment in Experiment,
      join: revision in GraphRevision,
      on: revision.id == experiment.graph_revision_id,
      join: graph in Graph,
      on: graph.id == revision.graph_id,
      where: experiment.status == "completed",
      select: %{
        id: experiment.id,
        kind: "simulation_report",
        graph_id: revision.graph_id,
        graph_revision_id: revision.id,
        graph_title: revision.title,
        analysis_ids: analysis_ids(experiment.analysis_id),
        revision_kind: type(revision.kind, :string),
        revision_number: revision.number,
        strategy: nil,
        output_graph_revision_id: type(fragment("NULL"), :binary_id),
        output_revision_kind: type(fragment("NULL"), :string),
        output_revision_number: type(fragment("NULL"), :integer),
        created_at: experiment.inserted_at
      }
  end

  defp optimization_items do
    from run in OptimizationRun,
      join: revision in GraphRevision,
      on: revision.id == run.graph_revision_id,
      join: graph in Graph,
      on: graph.id == revision.graph_id,
      left_join: output_revision in GraphRevision,
      on: output_revision.id == run.output_graph_revision_id,
      where: run.status == "completed",
      select: %{
        id: run.id,
        kind: "optimization_report",
        graph_id: revision.graph_id,
        graph_revision_id: revision.id,
        graph_title: revision.title,
        analysis_ids: analysis_ids(run.analysis_id),
        revision_kind: type(revision.kind, :string),
        revision_number: revision.number,
        strategy: run.strategy,
        output_graph_revision_id: run.output_graph_revision_id,
        output_revision_kind: type(output_revision.kind, :string),
        output_revision_number: output_revision.number,
        created_at: run.inserted_at
      }
  end

  defp filter_catalog(query, filters) do
    query
    |> maybe_search(filters.search)
    |> maybe_in(:kind, filters.types)
    |> maybe_in(:graph_id, filters.graph_ids)
    |> maybe_analysis(filters.analysis_ids)
    |> maybe_in(:strategy, filters.strategies)
    |> maybe_in(:revision_kind, filters.revision_kinds)
  end

  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    pattern = "%#{escape_search(search)}%"

    where(
      query,
      [item],
      fragment(
        "CASE ? WHEN 'graph' THEN 'Graph' WHEN 'simulation_report' THEN 'Simulation report' WHEN 'optimization_report' THEN 'Optimization report' END ILIKE ? ESCAPE '\\'",
        item.kind,
        ^pattern
      ) or
        fragment(
          "? || ' #' || CAST(? AS text) ILIKE ? ESCAPE '\\'",
          item.revision_kind,
          item.revision_number,
          ^pattern
        ) or
        fragment("? ILIKE ? ESCAPE '\\'", item.graph_title, ^pattern) or
        fragment(
          "EXISTS (SELECT 1 FROM unnest(?) AS analysis_id WHERE analysis_id::text ILIKE ? ESCAPE '\\')",
          item.analysis_ids,
          ^pattern
        ) or
        fragment(
          "EXISTS (SELECT 1 FROM workflow_runs WHERE id = ANY(?) AND title ILIKE ? ESCAPE '\\')",
          item.analysis_ids,
          ^pattern
        ) or
        fragment(
          "cardinality(?) > 1 AND 'multiple analyses' ILIKE ? ESCAPE '\\'",
          item.analysis_ids,
          ^pattern
        ) or
        fragment("? ILIKE ? ESCAPE '\\'", item.strategy, ^pattern) or
        fragment(
          "to_char(?, 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') ILIKE ? ESCAPE '\\'",
          item.created_at,
          ^pattern
        )
    )
  end

  defp escape_search(search) do
    search
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp maybe_in(query, _field, []), do: query
  defp maybe_in(query, field, values), do: where(query, [item], field(item, ^field) in ^values)

  defp maybe_analysis(query, []), do: query

  defp maybe_analysis(query, analysis_ids) do
    where(
      query,
      [item],
      fragment("? && ?", item.analysis_ids, type(^analysis_ids, {:array, :binary_id}))
    )
  end

  defp filter_options(catalog) do
    %{
      types: distinct_values(catalog, :kind),
      graphs:
        catalog
        |> group_by([item], [item.graph_id, item.graph_title])
        |> order_by([item], asc: item.graph_title, asc: item.graph_id)
        |> select([item], %{id: item.graph_id, title: item.graph_title})
        |> Repo.all(),
      analyses:
        catalog
        |> select([item], type(fragment("unnest(?)", item.analysis_ids), :binary_id))
        |> distinct(true)
        |> order_by([item], asc: type(fragment("unnest(?)", item.analysis_ids), :binary_id))
        |> Repo.all()
        |> analysis_options(),
      strategies: distinct_values(catalog, :strategy, true),
      revision_kinds: distinct_values(catalog, :revision_kind)
    }
  end

  defp distinct_values(catalog, field, reject_nil \\ false) do
    catalog =
      if reject_nil, do: where(catalog, [item], not is_nil(field(item, ^field))), else: catalog

    catalog
    |> distinct(true)
    |> order_by([item], asc: field(item, ^field))
    |> select([item], field(item, ^field))
    |> Repo.all()
  end

  defp analysis_options([]), do: []

  defp analysis_options(ids) do
    from(run in WorkflowRun,
      where: run.id in ^ids,
      order_by: [asc: run.title, asc: run.id],
      select: %{id: run.id, title: run.title}
    )
    |> Repo.all()
  end

  defp with_analyses(item, titles) do
    analyses =
      item.analysis_ids
      |> Enum.flat_map(fn id ->
        case Map.fetch(titles, id) do
          {:ok, title} -> [%{id: id, title: title}]
          :error -> []
        end
      end)

    item
    |> Map.delete(:analysis_ids)
    |> Map.put(:analyses, analyses)
  end
end
