defmodule NetworkDefense.Optimization.OptimizationReport do
  @moduledoc """
  Pure computation of an optimization report from a loaded OptimizationRun
  and its source graph revision.
  """

  alias NetworkDefense.Cvss

  alias NetworkDefense.DefenseActions.{
    BlockSegmentReachability,
    DefenseAction,
    PatchVulnerability,
    RevokeCredential
  }

  alias NetworkDefense.DefenseActions.Registry, as: DefenseActionsRegistry
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Optimization.OptimizationAction
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.ReportProgress

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @type t :: %__MODULE__{
          optimization_id: String.t(),
          graph_id: String.t(),
          graph_title: String.t(),
          graph: Graph.t(),
          graph_revision_id: String.t(),
          strategy: String.t(),
          requested_budget: integer(),
          used_budget: integer(),
          runtime_ms: integer(),
          actions: [map()]
        }

  defstruct [
    :optimization_id,
    :graph_id,
    :graph_title,
    :graph,
    :graph_revision_id,
    :strategy,
    :requested_budget,
    :used_budget,
    :runtime_ms,
    actions: []
  ]

  @doc """
  Returns a report from a completed run with preloaded actions (ordered by
  position) and the source graph revision the run was started against.
  """
  @spec generate(OptimizationRun.t(), Graph.t(), ReportProgress.progress_callback()) :: t()
  def generate(
        %OptimizationRun{} = run,
        %Graph{} = graph,
        on_progress \\ ReportProgress.noop()
      ) do
    Tracer.with_span "optimization.report.generate",
      attributes: %{
        "optimization.run_id": run.id,
        "graph.id": graph.id,
        "graph.revision_id": run.graph_revision_id,
        "optimization.strategy": run.strategy,
        "optimization.action_count": length(run.actions)
      } do
      Logger.debug("Optimization report generation started",
        event: "report.optimization.started",
        optimization_id: run.id,
        graph_id: graph.id,
        graph_revision_id: run.graph_revision_id,
        strategy: run.strategy,
        action_count: length(run.actions)
      )

      try do
        on_progress.(graph.id, graph.revision_id, 1, 2, "Loading optimization run")
        actions = Enum.map(run.actions, &action_summary(&1, graph))
        on_progress.(graph.id, graph.revision_id, 2, 2, "Building action summaries")

        report = %__MODULE__{
          optimization_id: run.id,
          graph_id: graph.id,
          graph_title: graph.title,
          graph: graph,
          graph_revision_id: run.graph_revision_id,
          strategy: run.strategy,
          requested_budget: run.requested_budget,
          used_budget: run.used_budget,
          runtime_ms: run.runtime_ms,
          actions: actions
        }

        Tracer.set_status(OpenTelemetry.status(:ok))

        Logger.debug("Optimization report generated",
          event: "report.optimization.completed",
          optimization_id: report.optimization_id,
          graph_id: report.graph_id,
          graph_revision_id: report.graph_revision_id,
          strategy: report.strategy,
          action_count: length(report.actions)
        )

        report
      rescue
        error ->
          Tracer.record_exception(error, __STACKTRACE__)
          Tracer.set_status(OpenTelemetry.status(:error))
          reraise error, __STACKTRACE__
      end
    end
  end

  defp action_summary(%OptimizationAction{} = action, graph) do
    action
    |> rebuild_action()
    |> action_summary(graph)
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

  defp action_summary(%BlockSegmentReachability{} = action, graph) do
    edge = Graph.edge(graph, action.edge_id)

    %{
      id: action.edge_id,
      label: policy_cut_label(edge, graph),
      kind: "Segment-boundary cut",
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

  defp rebuild_action(%OptimizationAction{} = action) do
    module = DefenseActionsRegistry.module_for_short(action.action_type)

    module.__struct__()
    |> DefenseAction.with_target_id(action.target_id)
    |> Map.put(:cost, action.cost)
  end

  defp policy_cut_label(nil, _graph), do: "Cut reachability policy"

  defp policy_cut_label(edge, graph) do
    source = node_label(Graph.node(graph, edge.from_id))
    target = node_label(Graph.node(graph, edge.to_id))
    "Cut #{source} to #{target} (#{policy_label(edge.data)})"
  end

  defp policy_label(%{protocol: protocol, port_start: nil, port_end: nil}),
    do: to_string(protocol)

  defp policy_label(%{protocol: protocol, port_start: port_start, port_end: port_end}) do
    "#{protocol}:#{port_start || "*"}-#{port_end || "*"}"
  end

  defp node_label(nil), do: "unknown target"
  defp node_label(%{data: %{name: name}}) when is_binary(name), do: name
  defp node_label(%{data: %{identifier: identifier}}) when is_binary(identifier), do: identifier
  defp node_label(%{id: id}), do: id

  defp cvss_score(%{data: %{cvss: cvss}}), do: Cvss.base_score(cvss)
  defp cvss_score(_), do: nil
end
