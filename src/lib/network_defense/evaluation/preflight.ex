defmodule NetworkDefense.Evaluation.Preflight do
  @moduledoc """
  Resolves the manifest source before any execution rows are created.

  Loads or generates the source graph, resolves the entry host, and checks
  mission feasibility when the manifest requires it. Returns field-path
  errors for the dashboard.
  """

  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Simulation.MissionImpact
  alias NetworkDefense.Topology.EnterpriseTopology

  @type error :: %{path: String.t(), message: String.t()}

  @spec preflight(map()) ::
          {:ok, %{graph_revision_id: String.t(), entry_host_id: String.t()}} | {:error, [error()]}
  def preflight(manifest) do
    with {:ok, graph} <- resolve_source(manifest),
         :ok <- check_mission_feasibility(graph, manifest),
         {:ok, entry_host_id} <- entry_host_id(graph, manifest),
         {:ok, graph} <- persist_source(graph, manifest) do
      {:ok, %{graph_revision_id: graph.revision_id, entry_host_id: entry_host_id}}
    else
      {:error, %{path: _, message: _} = error} -> {:error, [error]}
    end
  end

  @spec entry_host_id(Graph.t(), map()) :: {:ok, String.t()} | {:error, error()}
  def entry_host_id(graph, %{"attacker" => %{"entry_host" => entry_host}}) do
    case entry_host do
      %{"type" => "semantic_key", "value" => value} ->
        case find_host_by_name(graph, value) do
          nil -> {:error, %{path: "attacker.entry_host.value", message: "no host named #{value}"}}
          host -> {:ok, host.id}
        end

      %{"type" => "node_id", "value" => value} ->
        case Graph.node(graph, value) do
          %{type: Host} = host -> {:ok, host.id}
          _ -> {:error, %{path: "attacker.entry_host.value", message: "node is not a host"}}
        end
    end
  end

  defp resolve_source(%{"source" => %{"type" => "topology"} = source} = manifest) do
    graph =
      EnterpriseTopology.generate(
        hosts: source["hosts"],
        seed: source["seed"],
        title: "Evaluation #{manifest["id"]}"
      )

    {:ok, graph}
  end

  defp resolve_source(%{"source" => %{"type" => "graph_revision", "graph_revision_id" => id}}) do
    case Graphs.load_revision(id) do
      %Graph{} = graph ->
        {:ok, graph}

      nil ->
        {:error, %{path: "source.graph_revision_id", message: "graph revision not found"}}

      {:error, _reason} ->
        {:error, %{path: "source.graph_revision_id", message: "graph revision is invalid"}}
    end
  end

  defp persist_source(%Graph{revision_id: revision_id}, %{
         "source" => %{"type" => "graph_revision"}
       }),
       do: {:ok, %Graph{revision_id: revision_id}}

  defp persist_source(%Graph{} = graph, _manifest) do
    case Graphs.create(graph) do
      {:ok, graph} -> {:ok, graph}
      {:error, _reason} -> {:error, %{path: "source", message: "failed to persist topology"}}
    end
  end

  defp check_mission_feasibility(graph, %{"model_variants" => variants})
       when is_list(variants) do
    index =
      Enum.find_index(variants, fn variant ->
        is_map(variant) and variant["require_pre_attack_feasibility"] == true
      end)

    if is_nil(index) or MissionImpact.pre_attack_feasible?(graph) do
      :ok
    else
      {:error,
       %{
         path: "model_variants.#{index}.require_pre_attack_feasibility",
         message: "mission is not feasible before the attack"
       }}
    end
  end

  defp check_mission_feasibility(_graph, _manifest), do: :ok

  defp find_host_by_name(graph, name) do
    graph
    |> Graph.nodes()
    |> Enum.find(fn node -> node.type == Host and node.data.name == name end)
  end
end
