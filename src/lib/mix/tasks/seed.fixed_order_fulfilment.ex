defmodule Mix.Tasks.Seed.FixedOrderFulfilment do
  use Mix.Task

  @shortdoc "Seed or return the fixed order-fulfilment scenario revision and manifest"

  @moduledoc """
  Idempotently seeds the fixed order-fulfilment scenario graph and its local
  evaluation manifest, or returns the persisted revision and manifest on a
  subsequent run.

      mix seed.fixed_order_fulfilment
  """

  @requirements ["app.start"]

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.EvaluationManifest
  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Topology.FixedOrderFulfilmentScenario

  @impl Mix.Task
  def run(_args) do
    with {:ok, graph, revision_reused} <- ensure_initial_revision(),
         {:ok, severity_entry} <- entry_host_id(graph, "internet-entry"),
         {:ok, feasibility_entry} <- entry_host_id(graph, "order-gateway"),
         {:ok, severity_reused} <-
           ensure_manifest(
             graph.revision_id,
             severity_entry,
             FixedOrderFulfilmentScenario.manifest_id(),
             FixedOrderFulfilmentScenario.title(),
             &FixedOrderFulfilmentScenario.manifest_content/2
           ),
         {:ok, feasibility_reused} <-
           ensure_manifest(
             graph.revision_id,
             feasibility_entry,
             FixedOrderFulfilmentScenario.feasibility_manifest_id(),
             FixedOrderFulfilmentScenario.feasibility_manifest_title(),
             &FixedOrderFulfilmentScenario.feasibility_manifest_content/2
           ) do
      IO.puts(
        Jason.encode!(%{
          "graph_revision_id" => graph.revision_id,
          "manifest_id" => FixedOrderFulfilmentScenario.manifest_id(),
          "entry_host_id" => severity_entry,
          "revision_reused" => revision_reused,
          "manifest_reused" => severity_reused,
          "feasibility_manifest_id" => FixedOrderFulfilmentScenario.feasibility_manifest_id(),
          "feasibility_entry_host_id" => feasibility_entry,
          "feasibility_manifest_reused" => feasibility_reused
        })
      )
    else
      {:error, reason} -> Mix.raise(reason)
    end
  end

  defp ensure_initial_revision do
    case existing_initial_revision() do
      nil ->
        case Graphs.insert(FixedOrderFulfilmentScenario.graph()) do
          {:ok, graph} -> {:ok, graph, false}
          {:error, reason} -> {:error, "failed to persist scenario graph: #{inspect(reason)}"}
        end

      revision_id ->
        case Graphs.load_revision(revision_id) do
          %Graph{} = graph -> {:ok, graph, true}
          nil -> {:error, "scenario graph revision not found"}
          {:error, reason} -> {:error, "scenario graph revision is invalid: #{inspect(reason)}"}
        end
    end
  end

  defp existing_initial_revision do
    Graphs.list_summaries()
    |> Enum.find(fn summary ->
      summary.title == FixedOrderFulfilmentScenario.title() and summary.revisionKind == "initial"
    end)
    |> case do
      nil -> nil
      summary -> summary.revisionId
    end
  end

  defp entry_host_id(graph, host_name) do
    graph
    |> Graph.nodes()
    |> Enum.find(fn node -> node.type == Host and node.data.name == host_name end)
    |> case do
      %{id: id} -> {:ok, id}
      nil -> {:error, "#{host_name} host not found in the scenario graph"}
    end
  end

  defp ensure_manifest(graph_revision_id, entry_host_id, manifest_id, title, content_fun) do
    case Evaluation.get_by_manifest_id(manifest_id) do
      nil ->
        case Evaluation.save(%{
               manifest_id: manifest_id,
               title: title,
               content: content_fun.(graph_revision_id, entry_host_id)
             }) do
          {:ok, %EvaluationManifest{}} -> {:ok, false}
          {:error, reason} -> {:error, "failed to persist scenario manifest: #{inspect(reason)}"}
        end

      %EvaluationManifest{} = manifest ->
        if content_matches?(manifest, graph_revision_id, entry_host_id, content_fun) do
          {:ok, true}
        else
          update_manifest(
            manifest,
            graph_revision_id,
            entry_host_id,
            manifest_id,
            title,
            content_fun
          )
        end
    end
  end

  defp content_matches?(manifest, graph_revision_id, entry_host_id, content_fun) do
    manifest.content == content_fun.(graph_revision_id, entry_host_id)
  end

  defp update_manifest(
         manifest,
         graph_revision_id,
         entry_host_id,
         manifest_id,
         title,
         content_fun
       ) do
    case Evaluation.save(%{
           existing_manifest_id: manifest.id,
           manifest_id: manifest_id,
           title: title,
           content: content_fun.(graph_revision_id, entry_host_id)
         }) do
      {:ok, %EvaluationManifest{}} -> {:ok, false}
      {:error, reason} -> {:error, "failed to update scenario manifest: #{inspect(reason)}"}
    end
  end
end
