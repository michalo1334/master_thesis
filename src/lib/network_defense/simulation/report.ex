defmodule NetworkDefense.Simulation.Report do
  @moduledoc """
  Pure computation of simulation report statistics from loaded MultiState data.
  """

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Simulation.State
  alias NetworkDefense.Simulation.MultiState
  alias NetworkDefense.Graph.Graph

  @doc """
  Returns `report_data` map from a fully loaded MultiState with preloaded
  simulations and their iteration_steps (ordered by index ascending).
  """
  def generate(%MultiState{} = multi_state) do
    simulations = multi_state.simulations
    final_counts = final_foothold_counts(simulations)
    stats = blast_radius_stats(final_counts)

    %{
      multi_state_id: multi_state.id,
      graph_id: multi_state.graph_id,
      graph_title: graph_title(multi_state),
      graph_version_at_sim: multi_state.lock_version,
      simulation_count: length(simulations),
      iteration_count: multi_state.iteration_count,
      total_runtime_ms: multi_state.runtime_ms,
      kpis: kpis(stats, simulations),
      charts: %{
        blast_radius_distribution: distribution_charts(final_counts, stats),
        convergence: convergence_charts(simulations),
        action_stats: action_charts(simulations)
      }
    }
  end

  defp graph_title(%MultiState{graph: %Graph{title: title}}), do: title
  defp graph_title(_), do: "Unknown graph"

  defp final_foothold_counts(simulations) do
    simulations
    |> Enum.map(fn sim ->
      sim
      |> State.current_attacker_state()
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

  defp kpis(stats, simulations) do
    total_hosts = total_host_count(List.first(simulations))

    [
      %{
        label: "Simulation runs",
        value: Integer.to_string(length(simulations)),
        detail: "Monte Carlo trials completed",
        tone: "neutral"
      },
      %{
        label: "Expected blast radius",
        value: "#{Float.to_string(stats.mean)} hosts",
        detail: "Median: #{stats.median} compromised hosts",
        tone:
          if(total_hosts > 0 and stats.mean / total_hosts > 0.5, do: "warning", else: "neutral")
      },
      %{
        label: "Blast radius p95",
        value: "#{stats.p95} hosts",
        detail: "95th percentile worst-case",
        tone: "warning"
      },
      %{
        label: "Blast radius variance",
        value: Float.to_string(stats.variance),
        detail: "Spread across #{length(simulations)} runs",
        tone: "neutral"
      }
    ]
  end

  defp total_host_count(nil), do: 0

  defp total_host_count(%State{graph: %Graph{} = graph}) do
    graph |> Graph.nodes() |> length()
  end

  defp total_host_count(_), do: 0

  defp distribution_charts(counts, stats) do
    buckets = histogram_buckets(counts)
    cdf = cdf_series(Enum.sort(counts))

    [
      %{
        id: "blast-radius-histogram",
        title: "Observed blast-radius distribution",
        takeaway: "Outcomes concentrate around #{stats.median} compromised hosts.",
        aria_label: "Histogram of compromised hosts across simulation runs.",
        option: histogram_option(buckets)
      },
      %{
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

  defp convergence_charts(simulations) do
    counts =
      simulations
      |> Enum.map(fn sim ->
        sim
        |> State.current_attacker_state()
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
      %{
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

  defp action_charts(simulations) do
    action_counts = action_success_rates(simulations)

    if action_counts == [] do
      []
    else
      [
        %{
          id: "action-success-rate",
          title: "Attack action success rate",
          takeaway: "Action success rates by type across all simulation runs.",
          aria_label: "Bar chart of success rates per attack action type.",
          option: action_success_option(action_counts)
        }
      ]
    end
  end

  defp action_success_rates(simulations) do
    iterations =
      simulations
      |> Enum.flat_map(fn sim ->
        sim.iterations
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
