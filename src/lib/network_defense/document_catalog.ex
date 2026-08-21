defmodule NetworkDefense.DocumentCatalog do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Graph.{Graph, GraphRevision}
  alias NetworkDefense.DocumentCatalog.Kind
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment

  @graph_kind Kind.value(:graph)
  @simulation_report_kind Kind.value(:simulation_report)
  @optimization_report_kind Kind.value(:optimization_report)

  @graph_label Kind.label(:graph)
  @simulation_report_label Kind.label(:simulation_report)
  @optimization_report_label Kind.label(:optimization_report)

  @spec document_catalog(map()) :: map()
  def document_catalog(filters) do
    catalog = catalog_query()
    filtered = filter_catalog(catalog, filters)

    filter_options = filter_options(catalog)

    items =
      filtered
      |> order_by([item], desc: item.created_at, desc: item.id)
      |> limit(^filters.limit)
      |> offset(^filters.offset)
      |> Repo.all()
      |> Enum.map(fn item ->
        Map.update!(item, :created_at, &DateTime.to_iso8601/1)
      end)

    %{
      items: items,
      total_count: filtered |> select([item], count(item.id)) |> Repo.one(),
      filter_options: filter_options
    }
  end

  defp catalog_query do
    graph_items()
    |> union_all(^experiment_items())
    |> union_all(^optimization_items())
    |> subquery()
    |> then(&from(item in &1))
  end

  defp graph_items do
    from revision in GraphRevision,
      join: graph in Graph,
      on: graph.id == revision.graph_id,
      select: %{
        id: revision.id,
        kind: @graph_kind,
        graph_id: revision.graph_id,
        graph_revision_id: revision.id,
        graph_title: revision.title,
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
        kind: @simulation_report_kind,
        graph_id: revision.graph_id,
        graph_revision_id: revision.id,
        graph_title: revision.title,
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
        kind: @optimization_report_kind,
        graph_id: revision.graph_id,
        graph_revision_id: revision.id,
        graph_title: revision.title,
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
        "CASE ? WHEN ? THEN ? WHEN ? THEN ? WHEN ? THEN ? END ILIKE ? ESCAPE '\\'",
        item.kind,
        @graph_kind,
        @graph_label,
        @simulation_report_kind,
        @simulation_report_label,
        @optimization_report_kind,
        @optimization_report_label,
        ^pattern
      ) or
        fragment(
          "? || ' #' || CAST(? AS text) ILIKE ? ESCAPE '\\'",
          item.revision_kind,
          item.revision_number,
          ^pattern
        ) or
        fragment("? ILIKE ? ESCAPE '\\'", item.graph_title, ^pattern) or
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

  defp filter_options(catalog) do
    %{
      types: distinct_values(catalog, :kind),
      graphs:
        catalog
        |> group_by([item], [item.graph_id, item.graph_title])
        |> order_by([item], asc: item.graph_title, asc: item.graph_id)
        |> select([item], %{id: item.graph_id, title: item.graph_title})
        |> Repo.all(),
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
end
