defmodule NetworkDefense.Evaluation.OutputContract do
  @moduledoc """
  Deterministically regenerates the output-contract files for a completed
  evaluation run from its linked execution rows.

  The files are `manifest.resolved.json`, `graph.json`, `plans.jsonl`,
  `trials.csv`, `summary.csv`, and `checksums.txt`. Plans and trial rows are
  sorted and volatile timestamps are excluded. `graph.json` is the portable
  graph input from the immutable source graph revision.
  """

  import Ecto.Query

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Evaluation.EvaluationRun
  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.SimulationObjective
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.MissionImpact
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Observability
  alias NetworkDefense.Statistics

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @file_names [
    "manifest.resolved.json",
    "graph.json",
    "plans.jsonl",
    "trials.csv",
    "summary.csv",
    "checksums.txt"
  ]

  @spec file_names() :: [String.t()]
  def file_names, do: @file_names

  @spec files(EvaluationRun.t()) :: {:ok, [{String.t(), binary()}]} | {:error, term()}
  def files(%EvaluationRun{status: "completed"} = run) do
    with {:ok, graph} <- load_graph(run.source_graph_revision_id) do
      contents = [
        {"manifest.resolved.json", json(run.resolved_manifest)},
        {"graph.json", graph_json(graph)},
        {"plans.jsonl", plans_jsonl(run.id)},
        {"trials.csv", trials_csv(run.id, graph)},
        {"summary.csv", summary_csv(run.id)}
      ]

      {:ok, contents ++ [{"checksums.txt", checksums(contents)}]}
    end
  end

  def files(%EvaluationRun{}), do: {:error, :incomplete}
  def files(nil), do: {:error, :not_found}

  @spec archive(EvaluationRun.t()) :: {:ok, binary(), String.t()} | {:error, term()}
  def archive(%EvaluationRun{} = run) do
    Tracer.with_span "evaluation.export", attributes: export_span_attributes(run) do
      started_at = System.monotonic_time()
      log_export_started(run)

      try do
        result =
          with {:ok, files} <- files(run) do
            Tracer.set_attributes(%{"evaluation.export.file_count" => length(files)})

            entries =
              Enum.map(files, fn {name, content} -> {String.to_charlist(name), content} end)

            case :zip.create(String.to_charlist("evaluation.zip"), entries, [:memory]) do
              {:ok, {_name, zip_binary}} -> {:ok, zip_binary, "evaluation-#{run.id}.zip"}
              {:error, reason} -> {:error, reason}
            end
          end

        set_export_span_status(result)
        log_export_result(run, result, Observability.duration_ms(started_at))
        result
      rescue
        error ->
          Tracer.record_exception(error, __STACKTRACE__)
          Tracer.set_status(OpenTelemetry.status(:error))
          log_export_failed(run, error, Observability.duration_ms(started_at))
          reraise error, __STACKTRACE__
      after
        Observability.emit_duration([:network_defense, :evaluation, :export], started_at)
      end
    end
  end

  defp export_span_attributes(run) do
    %{
      "evaluation.run_id" => run.id,
      "evaluation.export.status" => run.status
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp set_export_span_status({:ok, _zip_binary, _filename}) do
    Tracer.set_attributes(%{"evaluation.export.status" => "completed"})
    Tracer.set_status(OpenTelemetry.status(:ok))
  end

  defp set_export_span_status(_result) do
    Tracer.set_attributes(%{"evaluation.export.status" => "failed"})
    Tracer.set_status(OpenTelemetry.status(:error))
  end

  defp log_export_started(run) do
    Logger.debug("Evaluation export started",
      event: "evaluation.export.started",
      evaluation_id: run.id,
      evaluation_run_id: run.id,
      status: run.status
    )
  end

  defp log_export_result(run, {:ok, zip_binary, filename}, runtime_ms) do
    Logger.debug("Evaluation export completed",
      event: "evaluation.export.completed",
      evaluation_id: run.id,
      evaluation_run_id: run.id,
      filename: filename,
      size_bytes: byte_size(zip_binary),
      runtime_ms: runtime_ms
    )
  end

  defp log_export_result(run, {:error, reason}, runtime_ms) do
    log_export_failed(run, reason, runtime_ms)
  end

  defp log_export_failed(run, reason, runtime_ms) do
    Logger.error("Evaluation export failed",
      event: "evaluation.export.failed",
      evaluation_id: run.id,
      evaluation_run_id: run.id,
      reason: reason,
      runtime_ms: runtime_ms
    )
  end

  defp load_graph(revision_id) do
    case Graphs.load_revision(revision_id) do
      %NetworkDefense.Graph.Graph{} = graph -> {:ok, graph}
      _ -> {:error, :not_found}
    end
  end

  defp json(value), do: Jason.encode!(value, pretty: true) <> "\n"

  defp graph_json(graph) do
    case GraphContract.from_domain(graph) do
      {:ok, wire_graph} ->
        wire_graph
        |> Map.put(:nodes, Enum.sort_by(wire_graph.nodes, & &1.id))
        |> Map.put(:edges, Enum.sort_by(wire_graph.edges, & &1.id))
        |> json()

      {:error, _changeset} ->
        raise "cannot serialize source graph for output contract"
    end
  end

  defp plans_jsonl(evaluation_run_id) do
    OptimizationRun
    |> where([run], run.evaluation_run_id == ^evaluation_run_id)
    |> order_by([run], asc: run.strategy, asc: run.requested_budget, asc: run.selection_seed)
    |> preload(:actions)
    |> Repo.all()
    |> Enum.map_join("\n", fn run ->
      %{
        id: run.id,
        strategy: run.strategy,
        requested_budget: run.requested_budget,
        selection_seed: run.selection_seed,
        used_budget: run.used_budget,
        action_count: length(run.actions),
        status: run.status
      }
      |> Jason.encode!()
    end)
    |> then(&(&1 <> "\n"))
  end

  defp trials_csv(evaluation_run_id, graph) do
    rows =
      Experiment
      |> where([experiment], experiment.evaluation_run_id == ^evaluation_run_id)
      |> order_by([experiment], asc: experiment.inserted_at, asc: experiment.id)
      |> preload(runs: :iterations)
      |> Repo.all()
      |> Enum.flat_map(fn experiment ->
        Enum.map(experiment.runs, fn run ->
          foothold_ids =
            run
            |> Run.current_attacker_state()
            |> AttackerState.foothold_nodes()

          %{
            experiment_id: experiment.id,
            plan_id: experiment.optimization_run_id,
            trial_index: run.trial_index,
            seed: run.seed,
            blast_radius: length(foothold_ids),
            mission_impact: MissionImpact.final(graph, foothold_ids)
          }
        end)
      end)
      |> Enum.sort_by(fn row ->
        {row.experiment_id, row.trial_index}
      end)

    csv(
      ["experiment_id", "plan_id", "trial_index", "seed", "blast_radius", "mission_impact"],
      rows
    )
  end

  defp summary_csv(evaluation_run_id) do
    rows =
      Experiment
      |> where([experiment], experiment.evaluation_run_id == ^evaluation_run_id)
      |> order_by([experiment], asc: experiment.inserted_at, asc: experiment.id)
      |> preload(runs: :iterations)
      |> Repo.all()
      |> Enum.map(fn experiment ->
        counts = Enum.map(experiment.runs, &SimulationObjective.final_foothold_count/1)
        stats = Statistics.summary(counts)

        %{
          experiment_id: experiment.id,
          plan_id: experiment.optimization_run_id,
          trial_count: length(experiment.runs),
          expected_blast_radius: stats.mean,
          median_blast_radius: stats.median,
          blast_radius_p95: stats.p95,
          blast_radius_p99: stats.p99,
          min_blast_radius: stats.min,
          max_blast_radius: stats.max
        }
      end)

    csv(
      [
        "experiment_id",
        "plan_id",
        "trial_count",
        "expected_blast_radius",
        "median_blast_radius",
        "blast_radius_p95",
        "blast_radius_p99",
        "min_blast_radius",
        "max_blast_radius"
      ],
      rows
    )
  end

  defp csv(headers, rows) do
    rows
    |> Enum.map(fn row ->
      Enum.map(headers, fn header ->
        row |> Map.fetch!(String.to_existing_atom(header)) |> to_csv_value()
      end)
    end)
    |> then(fn body -> [headers | body] end)
    |> Enum.map_join("\n", &Enum.join(&1, ","))
    |> then(&(&1 <> "\n"))
  end

  defp to_csv_value(nil), do: ""
  defp to_csv_value(value) when is_float(value), do: Float.to_string(value)
  defp to_csv_value(value) when is_integer(value), do: Integer.to_string(value)
  defp to_csv_value(value) when is_binary(value), do: value

  defp checksums(contents) do
    contents
    |> Enum.map_join("\n", fn {name, content} ->
      "#{name}  #{:crypto.hash(:sha256, content) |> Base.encode16(case: :lower)}"
    end)
    |> then(&(&1 <> "\n"))
  end
end
