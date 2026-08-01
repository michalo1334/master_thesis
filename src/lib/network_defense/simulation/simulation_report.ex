defmodule NetworkDefense.Simulation.SimulationReport do
  @moduledoc """
  Pure computation of simulation report statistics from loaded Experiment data.
  """

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Actions.AttemptedAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.SimulationReport.Charts
  alias NetworkDefense.Simulation.Run

  @type t :: %__MODULE__{
          experiment_id: String.t(),
          graph_id: String.t(),
          graph_title: String.t(),
          graph: Graph.t(),
          graph_revision_id: String.t(),
          run_count: non_neg_integer(),
          iteration_count: non_neg_integer(),
          total_runtime_ms: non_neg_integer(),
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
    summary: %{},
    charts: %Charts{}
  ]

  @doc """
  Returns a report from a fully loaded Experiment with preloaded runs
  and their iteration steps (ordered by index descending).
  """
  @spec generate(Experiment.t()) :: t()
  def generate(%Experiment{} = experiment) do
    runs = experiment.runs
    final_counts = final_foothold_counts(runs)
    stats = blast_radius_stats(final_counts)

    %__MODULE__{
      experiment_id: experiment.id,
      graph_id: experiment.graph.id,
      graph_title: graph_title(experiment),
      graph: experiment.graph,
      graph_revision_id: experiment.graph_revision_id,
      run_count: length(runs),
      iteration_count: experiment.iteration_count,
      total_runtime_ms: experiment.runtime_ms,
      summary: summary(stats, experiment.graph),
      charts: %Charts{
        histogram: histogram_buckets(final_counts),
        cdf: cdf_series(Enum.sort(final_counts)),
        convergence: convergence_series(final_counts),
        action_success: action_successes(runs),
        host_compromise: host_compromise_probabilities(runs, experiment.graph),
        edge_traversal: edge_traversal_probabilities(runs, experiment.graph)
      }
    }
  end

  defp graph_title(%Experiment{graph: %Graph{title: title}}), do: title
  defp graph_title(_), do: "Unknown graph"

  defp final_foothold_counts(runs) do
    runs
    |> Enum.map(fn run ->
      run
      |> Run.current_attacker_state()
      |> AttackerState.foothold_nodes()
      |> length()
    end)
  end

  defp blast_radius_stats(counts) do
    sorted = Enum.sort(counts)
    n = length(sorted)

    if n == 0 do
      %{mean: 0.0, median: 0, p95: 0, p99: 0, min: 0, max: 0, variance: 0.0}
    else
      mean = Enum.sum(sorted) / n
      variance = Enum.reduce(sorted, 0.0, fn x, acc -> acc + (x - mean) * (x - mean) end) / n

      %{
        mean: mean,
        median: percentile(sorted, n, 0.5),
        p95: percentile(sorted, n, 0.95),
        p99: percentile(sorted, n, 0.99),
        min: List.first(sorted),
        max: List.last(sorted),
        variance: variance
      }
    end
  end

  defp percentile(sorted, n, p) when n > 0 do
    idx = max(0, Kernel.trunc(p * (n - 1)))
    Enum.at(sorted, idx)
  end

  defp summary(stats, graph) do
    %{
      expected_blast_radius: stats.mean,
      median_blast_radius: stats.median,
      blast_radius_p95: stats.p95,
      blast_radius_p99: stats.p99,
      min_blast_radius: stats.min,
      max_blast_radius: stats.max,
      blast_radius_variance: stats.variance,
      host_count: total_host_count(graph)
    }
  end

  defp total_host_count(%Graph{} = graph) do
    graph
    |> Graph.nodes()
    |> length()
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

  defp edge_traversal_probabilities(runs, %Graph{} = graph) do
    edge_ids = graph |> Graph.edges() |> Enum.map(& &1.id)

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
