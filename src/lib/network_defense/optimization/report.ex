defmodule NetworkDefense.Optimization.Report do
  @moduledoc false

  alias NetworkDefense.Cvss

  alias NetworkDefense.DefenseActions.{
    BlockReachability,
    DefenseAction,
    PatchVulnerability,
    RevokeCredential
  }

  alias NetworkDefense.Graph.Graph

  def build(
        graph,
        strategy_id,
        requested_budget,
        %{actions: actions, budget_used: budget_used},
        runtime_us
      ) do
    %{
      strategy: strategy_id,
      requested_budget: requested_budget,
      used_budget: budget_used,
      runtime_ms: div(runtime_us, 1000),
      actions: Enum.map(actions, &action_summary(&1, graph))
    }
  end

  defp action_summary(%PatchVulnerability{} = action, graph) do
    edge = Graph.edge(graph, action.edge_id)
    vulnerability = edge && Graph.node(graph, edge.to_id)
    identifier = vulnerability && vulnerability.data.identifier

    %{
      id: action.edge_id,
      label: "Patch #{identifier || action.edge_id}",
      kind: "Vulnerability patch",
      cvss_score: cvss_score(vulnerability),
      cost: DefenseAction.cost(action)
    }
  end

  defp action_summary(%BlockReachability{} = action, graph) do
    edge = Graph.edge(graph, action.edge_id)

    %{
      id: action.edge_id,
      label: "Block #{edge_label(edge, graph)}",
      kind: "Network segmentation",
      cost: DefenseAction.cost(action)
    }
  end

  defp action_summary(%RevokeCredential{} = action, graph) do
    credential = Graph.node(graph, action.credential_id)

    %{
      id: action.credential_id,
      label: "Revoke #{node_label(credential)}",
      kind: "Credential revocation",
      cost: DefenseAction.cost(action)
    }
  end

  defp edge_label(nil, _graph), do: "reachability"

  defp edge_label(edge, graph) do
    "#{node_label(Graph.node(graph, edge.from_id))} to #{node_label(Graph.node(graph, edge.to_id))}"
  end

  defp node_label(nil), do: "unknown target"
  defp node_label(%{data: %{name: name}}) when is_binary(name), do: name
  defp node_label(%{data: %{identifier: identifier}}) when is_binary(identifier), do: identifier
  defp node_label(%{id: id}), do: id

  defp cvss_score(%{data: %{cvss: cvss}}), do: Cvss.base_score(cvss)
  defp cvss_score(_), do: nil
end
