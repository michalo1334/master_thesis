defmodule NetworkDefense.Simulation.SimulationReport do
  @moduledoc """
  Pure computation of simulation report statistics from loaded Experiment data.
  """

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Actions.AttemptedAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Optimization.SimulationObjective
  alias NetworkDefense.ReportProgress
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.MissionImpact
  alias NetworkDefense.Simulation.SimulationReport.Charts
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Statistics

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @type t :: %__MODULE__{
          experiment_id: String.t(),
          graph_id: String.t(),
          graph_title: String.t(),
          graph: Graph.t(),
          graph_revision_id: String.t(),
          operational_flows: [map()],
          run_count: non_neg_integer(),
          iteration_count: non_neg_integer(),
          total_runtime_ms: non_neg_integer(),
          pre_attack_capability_statuses: [map()],
          pre_attack_feasible: boolean(),
          summary: map(),
          charts: Charts.t()
        }

  defstruct [
    :experiment_id,
    :graph_id,
    :graph_title,
    :graph,
    :graph_revision_id,
    :run_count,
    :iteration_count,
    :total_runtime_ms,
    pre_attack_capability_statuses: [],
    pre_attack_feasible: true,
    operational_flows: [],
    summary: %{},
    charts: %Charts{}
  ]

  @doc """
  Returns a report from a fully loaded Experiment with preloaded runs
  and their iteration steps (ordered by index descending).
  """
  @spec generate(Experiment.t(), ReportProgress.progress_callback()) :: t()
  def generate(%Experiment{} = experiment, on_progress \\ ReportProgress.noop()) do
    Tracer.with_span "simulation.report.generate",
      attributes: %{
        "simulation.experiment_id": experiment.id,
        "graph.id": experiment.graph.id,
        "graph.revision_id": experiment.graph_revision_id,
        "simulation.run_count": length(experiment.runs),
        "simulation.iteration_count": experiment.iteration_count
      } do
      Logger.debug("Simulation report generation started",
        event: "report.simulation.started",
        experiment_id: experiment.id,
        graph_id: experiment.graph.id,
        graph_revision_id: experiment.graph_revision_id,
        run_count: length(experiment.runs),
        iteration_count: experiment.iteration_count
      )

      try do
        graph = experiment.graph
        runs = experiment.runs
        on_progress.(graph.id, graph.revision_id, 1, 6, "Loading experiment data")
        final_counts = final_foothold_counts(runs)
        blast_radius_stats = Statistics.summary(final_counts)
        on_progress.(graph.id, graph.revision_id, 2, 6, "Computing blast radius statistics")
        final_mission_impacts = final_mission_impacts(runs, graph)
        mission_impact_stats = Statistics.summary(final_mission_impacts)
        on_progress.(graph.id, graph.revision_id, 3, 6, "Computing mission impact statistics")

        operational_flows =
          graph
          |> MaterializeReachability.materialize()
          |> MaterializeReachability.operational_flows()

        on_progress.(graph.id, graph.revision_id, 4, 6, "Materializing operational flows")

        action_success = action_successes(runs)
        on_progress.(graph.id, graph.revision_id, 5, 6, "Aggregating action results")

        host_compromise = host_compromise_probabilities(runs, graph)
        capability_impact = capability_impact_probabilities(runs, graph)
        edge_traversal = edge_traversal_probabilities(runs, graph, operational_flows)
        on_progress.(graph.id, graph.revision_id, 6, 6, "Computing compromise probabilities")

        report = %__MODULE__{
          experiment_id: experiment.id,
          graph_id: graph.id,
          graph_title: graph_title(experiment),
          graph: graph,
          graph_revision_id: experiment.graph_revision_id,
          operational_flows: operational_flows,
          run_count: length(runs),
          iteration_count: experiment.iteration_count,
          total_runtime_ms: experiment.runtime_ms,
          pre_attack_capability_statuses: MissionImpact.pre_attack_status(graph),
          pre_attack_feasible: MissionImpact.pre_attack_feasible?(graph),
          summary: summary(blast_radius_stats, mission_impact_stats, graph),
          charts: %Charts{
            histogram: histogram_buckets(final_counts),
            cdf: cdf_series(Enum.sort(final_counts)),
            convergence: convergence_series(final_counts),
            action_success: action_success,
            host_compromise: host_compromise,
            capability_impact: capability_impact,
            edge_traversal: edge_traversal
          }
        }

        Tracer.set_status(OpenTelemetry.status(:ok))

        Logger.debug("Simulation report generated",
          event: "report.simulation.completed",
          experiment_id: report.experiment_id,
          graph_id: report.graph_id,
          graph_revision_id: report.graph_revision_id,
          run_count: report.run_count,
          operational_flow_count: length(report.operational_flows)
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

  defp graph_title(%Experiment{graph: %Graph{title: title}}), do: title

  defp final_foothold_counts(runs) do
    Enum.map(runs, &SimulationObjective.final_foothold_count/1)
  end

  defp final_mission_impacts(runs, graph) do
    Enum.map(runs, fn run ->
      run
      |> Run.current_attacker_state()
      |> AttackerState.foothold_nodes()
      |> then(&MissionImpact.final(graph, &1))
    end)
  end

  defp summary(blast_radius_stats, mission_impact_stats, graph) do
    %{
      expected_blast_radius: blast_radius_stats.mean,
      median_blast_radius: blast_radius_stats.median,
      blast_radius_p95: blast_radius_stats.p95,
      blast_radius_p99: blast_radius_stats.p99,
      min_blast_radius: blast_radius_stats.min,
      max_blast_radius: blast_radius_stats.max,
      blast_radius_variance: blast_radius_stats.variance,
      expected_mission_impact: mission_impact_stats.mean,
      median_mission_impact: mission_impact_stats.median,
      mission_impact_p95: mission_impact_stats.p95,
      mission_impact_p99: mission_impact_stats.p99,
      min_mission_impact: mission_impact_stats.min,
      max_mission_impact: mission_impact_stats.max,
      mission_impact_variance: mission_impact_stats.variance,
      host_count: total_host_count(graph)
    }
  end

  defp total_host_count(%Graph{} = graph) do
    graph
    |> Graph.nodes()
    |> Enum.count(&match?(%{type: NetworkDefense.Nodes.Host}, &1))
  end

  defp histogram_buckets(counts) do
    {min_val, max_val} = if counts == [], do: {0, 1}, else: {Enum.min(counts), Enum.max(counts)}

    bucket_size =
      cond do
        max_val - min_val <= 5 -> 1
        max_val - min_val <= 20 -> 2
        max_val - min_val <= 50 -> 5
        true -> 10
      end

    num_buckets = max(1, Kernel.trunc((max_val - min_val) / bucket_size) + 1)

    0..(num_buckets - 1)
    |> Enum.map(fn i ->
      lower = min_val + i * bucket_size
      upper = lower + bucket_size - 1

      count =
        Enum.count(counts, fn c ->
          c >= lower and c <= upper
        end)

      %{lower_bound: lower, upper_bound: upper, count: count}
    end)
  end

  defp cdf_series(sorted) do
    total = length(sorted)
    if total == 0, do: []

    sorted
    |> Enum.with_index()
    |> Enum.map(fn {val, idx} ->
      %{compromised_hosts: val, cumulative_probability: (idx + 1) / total}
    end)
  end

  defp convergence_series(counts) do
    {_, _, series} =
      counts
      |> Enum.reduce({0.0, 0, []}, fn count, {sum, n, acc} ->
        sum = sum + count
        n = n + 1
        mean = sum / n
        # Sample at intervals to bound the report payload.
        step = max(1, div(length(counts), 20))

        next =
          if n == 1 or rem(n, step) == 0 or n == length(counts) do
            [%{run: n, mean_blast_radius: mean} | acc]
          else
            acc
          end

        {sum, n, next}
      end)

    Enum.reverse(series)
  end

  defp action_successes(runs) do
    iterations =
      runs
      |> Enum.flat_map(fn run ->
        run.iterations
      end)
      |> Enum.filter(fn iter -> iter.attempted_action != nil end)

    iterations
    |> Enum.group_by(fn iter ->
      iter.attempted_action |> AttemptedAction.action() |> action_type_label()
    end)
    |> Enum.map(fn {action_type, group} ->
      %{
        action_type: action_type,
        attempts: length(group),
        successes: Enum.count(group, & &1.success?)
      }
    end)
    |> Enum.sort_by(& &1.action_type)
  end

  defp host_compromise_probabilities(runs, %Graph{} = graph) do
    host_ids =
      graph
      |> Graph.nodes()
      |> Enum.filter(&match?(%{type: NetworkDefense.Nodes.Host}, &1))
      |> Enum.map(& &1.id)

    probabilities_for_runs(
      host_ids,
      runs,
      fn run ->
        run
        |> Run.current_attacker_state()
        |> AttackerState.foothold_nodes()
      end,
      :host_id,
      :compromise_probability
    )
  end

  defp capability_impact_probabilities(runs, %Graph{} = graph) do
    capability_ids =
      graph
      |> Graph.nodes()
      |> Enum.filter(&match?(%{type: NetworkDefense.Nodes.MissionCapability}, &1))
      |> Enum.map(& &1.id)

    probabilities_for_runs(
      capability_ids,
      runs,
      fn run ->
        run
        |> Run.current_attacker_state()
        |> AttackerState.foothold_nodes()
        |> then(&MissionImpact.capability_statuses(graph, &1))
        |> Enum.filter(& &1.down?)
        |> Enum.map(& &1.capability_id)
      end,
      :capability_id,
      :down_probability
    )
  end

  defp edge_traversal_probabilities(runs, %Graph{} = graph, operational_flows) do
    edge_ids =
      graph
      |> Graph.edges()
      |> Enum.map(& &1.id)
      |> Kernel.++(Enum.map(operational_flows, & &1.id))
      |> Enum.uniq()

    probabilities_for_runs(
      edge_ids,
      runs,
      fn run ->
        run.iterations
        |> Enum.filter(& &1.success?)
        |> Enum.flat_map(fn iteration ->
          iteration.attempted_action
          |> AttemptedAction.action()
          |> Map.get(:supporting_edge_ids, [])
        end)
      end,
      :edge_id,
      :traversal_probability
    )
  end

  defp probabilities_for_runs(ids, runs, values_for_run, id_key, probability_key) do
    counts =
      Enum.reduce(runs, Map.new(ids, &{&1, 0}), fn run, counts ->
        run
        |> values_for_run.()
        |> MapSet.new()
        |> Enum.reduce(counts, fn id, counts ->
          Map.update(counts, id, 0, &(&1 + 1))
        end)
      end)

    total = length(runs)

    Enum.map(ids, fn id ->
      %{id_key => id, probability_key => if(total == 0, do: 0.0, else: counts[id] / total)}
    end)
  end

  defp action_type_label(action) do
    case action do
      %{__struct__: struct} -> struct |> Module.split() |> List.last()
      %{"__struct__" => struct} -> struct |> String.split(".") |> List.last()
      _ -> "Unknown"
    end
  end
end
