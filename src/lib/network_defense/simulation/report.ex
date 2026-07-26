defmodule NetworkDefense.Simulation.Report do
  @moduledoc """
  Pure computation of simulation report statistics from loaded Experiment data.
  """

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Report.{Chart, Charts, Kpi}
  alias NetworkDefense.Simulation.Run

  @type t :: %__MODULE__{
          experiment_id: String.t(),
          graph_id: String.t(),
          graph_title: String.t(),
          graph_version_at_sim: integer(),
          run_count: non_neg_integer(),
          iteration_count: non_neg_integer(),
          total_runtime_ms: non_neg_integer(),
          kpis: [Kpi.t()],
          charts: Charts.t()
        }

  defstruct [
    :experiment_id,
    :graph_id,
    :graph_title,
    :graph_version_at_sim,
    :run_count,
    :iteration_count,
    :total_runtime_ms,
    kpis: [],
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
      graph_id: experiment.graph_id,
      graph_title: graph_title(experiment),
      graph_version_at_sim: experiment.lock_version,
      run_count: length(runs),
      iteration_count: experiment.iteration_count,
      total_runtime_ms: experiment.runtime_ms,
      kpis: kpis(stats, runs),
      charts: %Charts{
        blast_radius_distribution: distribution_charts(final_counts, stats),
        convergence: convergence_charts(runs),
        action_stats: action_charts(runs)
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
        mean: round(mean * 10) / 10,
        median: percentile(sorted, n, 0.5),
        p95: percentile(sorted, n, 0.95),
        p99: percentile(sorted, n, 0.99),
        min: List.first(sorted),
        max: List.last(sorted),
        variance: round(variance * 10) / 10
      }
    end
  end

  defp percentile(sorted, n, p) when n > 0 do
    idx = max(0, Kernel.trunc(p * (n - 1)))
    Enum.at(sorted, idx)
  end

  defp kpis(stats, runs) do
    total_hosts = total_host_count(List.first(runs))

    [
      %Kpi{
        label: "Simulation runs",
        value: Integer.to_string(length(runs)),
        detail: "Monte Carlo trials completed",
        tone: "neutral"
      },
      %Kpi{
        label: "Expected blast radius",
        value: "#{Float.to_string(stats.mean)} hosts",
        detail: "Median: #{stats.median} compromised hosts",
        tone:
          if(total_hosts > 0 and stats.mean / total_hosts > 0.5, do: "warning", else: "neutral")
      },
      %Kpi{
        label: "Blast radius p95",
        value: "#{stats.p95} hosts",
        detail: "95th percentile worst-case",
        tone: "warning"
      },
      %Kpi{
        label: "Blast radius variance",
        value: Float.to_string(stats.variance),
        detail: "Spread across #{length(runs)} runs",
        tone: "neutral"
      }
    ]
  end

  defp total_host_count(nil), do: 0

  defp total_host_count(%Run{graph: %Graph{} = graph}) do
    graph |> Graph.nodes() |> length()
  end

  defp total_host_count(_), do: 0

  defp distribution_charts(counts, stats) do
    buckets = histogram_buckets(counts)
    cdf = cdf_series(Enum.sort(counts))

    [
      %Chart{
        id: "blast-radius-histogram",
        title: "Observed blast-radius distribution",
        takeaway: "Outcomes concentrate around #{stats.median} compromised hosts.",
        aria_label: "Histogram of compromised hosts across simulation runs.",
        option: histogram_option(buckets)
      },
      %Chart{
        id: "cumulative-distribution",
        title: "Cumulative blast-radius distribution",
        takeaway: "Most simulated attacks compromise #{stats.p95} or fewer hosts.",
        aria_label: "Area chart of the cumulative distribution of compromised hosts.",
        option: cdf_option(cdf)
      }
    ]
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
      label = "#{lower}-#{upper}"

      count =
        Enum.count(counts, fn c ->
          c >= lower and c <= upper
        end)

      %{label: label, count: count}
    end)
  end

  defp cdf_series(sorted) do
    total = length(sorted)
    if total == 0, do: []

    sorted
    |> Enum.with_index()
    |> Enum.map(fn {val, idx} ->
      %{x: val, y: Float.round((idx + 1) / total * 100, 1)}
    end)
  end

  defp convergence_charts(runs) do
    counts =
      runs
      |> Enum.map(fn run ->
        run
        |> Run.current_attacker_state()
        |> AttackerState.foothold_nodes()
        |> length()
      end)

    series = convergence_series(counts)

    takeaway =
      case List.last(series) do
        nil -> "No completed simulation runs are available."
        %{mean: mean} -> "Expected blast radius stabilizes near #{Float.round(mean, 1)} hosts."
      end

    [
      %Chart{
        id: "mean-convergence",
        title: "Monte Carlo convergence",
        takeaway: takeaway,
        aria_label: "Line chart showing mean blast radius as Monte Carlo runs increase.",
        option: convergence_option(series)
      }
    ]
  end

  defp convergence_series(counts) do
    {_, _, series} =
      counts
      |> Enum.reduce({0.0, 0, []}, fn count, {sum, n, acc} ->
        sum = sum + count
        n = n + 1
        mean = Float.round(sum / n, 1)
        # display at intervals to keep chart readable
        step = max(1, div(length(counts), 20))

        next =
          if n == 1 or rem(n, step) == 0 or n == length(counts) do
            [%{run: n, mean: mean} | acc]
          else
            acc
          end

        {sum, n, next}
      end)

    Enum.reverse(series)
  end

  defp action_charts(runs) do
    action_counts = action_success_rates(runs)

    if action_counts == [] do
      []
    else
      [
        %Chart{
          id: "action-success-rate",
          title: "Attack action success rate",
          takeaway: "Action success rates by type across all simulation runs.",
          aria_label: "Bar chart of success rates per attack action type.",
          option: action_success_option(action_counts)
        }
      ]
    end
  end

  defp action_success_rates(runs) do
    iterations =
      runs
      |> Enum.flat_map(fn run ->
        run.iterations
      end)
      |> Enum.filter(fn iter -> iter.attempted_action != nil end)

    iterations
    |> Enum.group_by(fn iter ->
      action_type_label(iter.attempted_action)
    end)
    |> Enum.map(fn {type, group} ->
      total = length(group)
      successes = Enum.count(group, & &1.success?)
      rate = if total == 0, do: 0, else: Float.round(successes / total * 100, 1)
      %{type: type, total: total, success_rate: rate}
    end)
  end

  defp action_type_label(action) do
    case action do
      %{__struct__: struct} -> struct |> Module.split() |> List.last()
      %{"__struct__" => struct} -> struct |> String.split(".") |> List.last()
      _ -> "Unknown"
    end
  end

  # --- ECharts options builders ---

  defp axis_style do
    %{
      axisLine: %{lineStyle: %{color: "#aeb8c5"}},
      axisLabel: %{color: "#4d5a68", fontSize: 11}
    }
  end

  defp histogram_option(buckets) do
    %{
      animation: false,
      aria: %{enabled: true},
      color: ["#1769aa"],
      textStyle: %{fontFamily: "Segoe UI, Arial, sans-serif"},
      grid: %{left: 46, right: 18, top: 20, bottom: 34},
      tooltip: %{
        trigger: "axis",
        backgroundColor: "#172234",
        borderWidth: 0,
        textStyle: %{color: "#ffffff"},
        valueFormatter: "{c} runs"
      },
      xAxis: %{
        type: "category",
        data: Enum.map(buckets, & &1.label),
        axisLine: axis_style().axisLine,
        axisLabel: axis_style().axisLabel,
        name: "Compromised hosts",
        nameLocation: "middle",
        nameGap: 28
      },
      yAxis: %{
        type: "value",
        name: "Runs",
        axisLine: axis_style().axisLine,
        axisLabel: axis_style().axisLabel
      },
      series: [
        %{
          name: "Simulation runs",
          type: "bar",
          data: Enum.map(buckets, & &1.count),
          barMaxWidth: 34,
          itemStyle: %{borderRadius: [3, 3, 0, 0]}
        }
      ]
    }
  end

  defp cdf_option(points) do
    %{
      animation: false,
      aria: %{enabled: true},
      color: ["#1769aa"],
      textStyle: %{fontFamily: "Segoe UI, Arial, sans-serif"},
      grid: %{left: 48, right: 20, top: 20, bottom: 36},
      tooltip: %{
        trigger: "axis",
        backgroundColor: "#172234",
        borderWidth: 0,
        textStyle: %{color: "#ffffff"},
        valueFormatter: "{c}%"
      },
      xAxis: %{
        type: "category",
        name: "Compromised hosts",
        nameLocation: "middle",
        nameGap: 28,
        data: Enum.map(points, & &1.x),
        axisLine: axis_style().axisLine,
        axisLabel: axis_style().axisLabel
      },
      yAxis: %{
        type: "value",
        name: "Runs (%)",
        min: 0,
        max: 100,
        axisLine: axis_style().axisLine,
        axisLabel: %{color: "#4d5a68", fontSize: 11, formatter: "{value}%"}
      },
      series: [
        %{
          name: "Cumulative runs",
          type: "line",
          smooth: true,
          data: Enum.map(points, & &1.y),
          areaStyle: %{color: "#b8d6ee"},
          lineStyle: %{width: 2.5}
        }
      ]
    }
  end

  defp convergence_option(series) do
    run_values = Enum.map(series, & &1.run)
    mean_values = Enum.map(series, & &1.mean)

    %{
      animation: false,
      aria: %{enabled: true},
      color: ["#1769aa"],
      textStyle: %{fontFamily: "Segoe UI, Arial, sans-serif"},
      grid: %{left: 48, right: 20, top: 20, bottom: 38},
      tooltip: %{
        trigger: "axis",
        backgroundColor: "#172234",
        borderWidth: 0,
        textStyle: %{color: "#ffffff"}
      },
      xAxis: %{
        type: "category",
        name: "Completed runs",
        nameLocation: "middle",
        nameGap: 28,
        data: run_values,
        axisLine: axis_style().axisLine,
        axisLabel: axis_style().axisLabel
      },
      yAxis: %{
        type: "value",
        name: "Mean hosts",
        axisLine: axis_style().axisLine,
        axisLabel: axis_style().axisLabel
      },
      series: [
        %{
          name: "Mean blast radius",
          type: "line",
          data: mean_values,
          smooth: true,
          lineStyle: %{width: 2.5}
        }
      ]
    }
  end

  defp action_success_option(action_stats) do
    %{
      animation: false,
      aria: %{enabled: true},
      color: ["#4f8bc2", "#b9574f"],
      textStyle: %{fontFamily: "Segoe UI, Arial, sans-serif"},
      grid: %{left: 48, right: 18, top: 28, bottom: 38},
      legend: %{top: 0, selectedMode: true, textStyle: %{color: "#4d5a68"}},
      tooltip: %{
        trigger: "axis",
        backgroundColor: "#172234",
        borderWidth: 0,
        textStyle: %{color: "#ffffff"},
        valueFormatter: "{c}%"
      },
      xAxis: %{
        type: "category",
        data: Enum.map(action_stats, & &1.type),
        axisLine: axis_style().axisLine,
        axisLabel: %{color: "#4d5a68", fontSize: 10}
      },
      yAxis: %{
        type: "value",
        name: "Rate (%)",
        max: 100,
        axisLine: axis_style().axisLine,
        axisLabel: %{color: "#4d5a68", fontSize: 11, formatter: "{value}%"}
      },
      series: [
        %{
          name: "Success rate",
          type: "bar",
          data: Enum.map(action_stats, & &1.success_rate),
          barMaxWidth: 38,
          itemStyle: %{borderRadius: [3, 3, 0, 0]}
        }
      ]
    }
  end
end
