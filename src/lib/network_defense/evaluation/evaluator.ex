defmodule NetworkDefense.Evaluation.Evaluator do
  @moduledoc """
  Executes an evaluation run against its resolved source graph revision.

  The lifecycle is:

    1. Load the resolved manifest and source graph revision.
    2. Build the attack-seed schedule once.
    3. Select every plan before post-defense trials start.
    4. Run the baseline and each post-defense experiment with the shared
       schedule.
    5. Mark the evaluation run complete only after every experiment completes.

  Plans and experiments are persisted through the existing
  `optimization_runs`, `experiments`, and `simulation_runs` tables. The run is
  idempotent: a completed run is returned as-is, and resuming a partially
  completed run reuses already-persisted plans and experiments instead of
  duplicating them.
  """

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.{EvaluationRuns, PlanPreview, SeedSchedule}
  alias NetworkDefense.Graph.{Graph, Graphs}

  alias NetworkDefense.Optimization.{
    CvssStrategy,
    NullStrategy,
    OptimizationAction,
    ModelVariant,
    OptimizationRun,
    OptimizationRuns,
    Optimizer,
    RandomStrategy,
    SimulatedAnnealingStrategy,
    SimulationInformedStrategy,
    SimulationStrategy,
    TopologySegmentationStrategy
  }

  alias NetworkDefense.Simulation.{Experiment, Experiments}
  alias NetworkDefense.Simulations
  alias NetworkDefense.Observability

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @spec run(NetworkDefense.Evaluation.EvaluationRun.t()) ::
          {:ok, NetworkDefense.Evaluation.EvaluationRun.t()} | {:error, term()}
  def run(%{status: "completed"} = run), do: {:ok, run}

  def run(%{status: "failed"} = run), do: {:ok, run}
  def run(%{status: "cancelled"} = run), do: {:ok, run}

  def run(%{source_graph_revision_id: revision_id} = run) do
    Tracer.with_span "evaluation.run", attributes: evaluation_span_attributes(run) do
      started_at = System.monotonic_time()
      log_evaluation_started(run)

      try do
        result = execute_run(run, revision_id)
        set_evaluation_span_status(result)
        log_evaluation_result(run, result, Observability.duration_ms(started_at))
        result
      rescue
        error ->
          Tracer.record_exception(error, __STACKTRACE__)
          Tracer.set_status(OpenTelemetry.status(:error))
          failed_run = failed_run(run, error)
          log_evaluation_failed(failed_run, error, Observability.duration_ms(started_at))
          reraise error, __STACKTRACE__
      after
        Observability.emit_duration([:network_defense, :evaluation, :run], started_at)
      end
    end
  end

  defp execute_run(run, revision_id) do
    with {:ok, graph} <- load_source(revision_id),
         :ok <- set_graph_span_attributes(graph),
         {:ok, schedule} <- build_schedule(run),
         :ok <- emit_progress(run.id, graph, 0, progress_total(run), "Selecting plans"),
         {:ok, plans} <- select_plans(run, graph, schedule),
         :ok <- run_experiments(run, graph, schedule, plans) do
      EvaluationRuns.complete(run)
    else
      {:error, reason} -> fail(run, reason)
    end
  end

  defp evaluation_span_attributes(run) do
    manifest = resolved_manifest(run)

    compact_attributes(%{
      "evaluation.run_id" => run.id,
      "network_defense.correlation.id" => run.id,
      "evaluation.manifest_id" => manifest["id"],
      "evaluation.schema_version" => manifest["schema_version"],
      "evaluation.model_version" => manifest["model_version"],
      "evaluation.seed" => get_in(manifest, ["evaluation", "seed"]),
      "evaluation.plan_count" => plan_count(run),
      "evaluation.trial_count" => trial_count(run),
      "graph.revision_id" => run.source_graph_revision_id
    })
  end

  defp plan_span_attributes(run, graph, model_variant, strategy, budget, selection_seed) do
    compact_attributes(%{
      "evaluation.run_id" => run.id,
      "network_defense.correlation.id" => run.id,
      "evaluation.plan.model_variant" => ModelVariant.to_wire(model_variant),
      "evaluation.plan.strategy" => strategy,
      "evaluation.plan.requested_budget" => budget,
      "evaluation.plan.selection_seed" => selection_seed,
      "graph.id" => graph.id,
      "graph.revision_id" => graph.revision_id
    })
  end

  defp experiment_span_attributes(experiment, graph) do
    compact_attributes(%{
      "evaluation.run_id" => experiment.evaluation_run_id,
      "network_defense.correlation.id" => experiment.evaluation_run_id,
      "evaluation.experiment_id" => experiment.id,
      "evaluation.plan_id" => experiment.optimization_run_id,
      "evaluation.experiment.type" => experiment_type(experiment),
      "evaluation.trial_count" => experiment.total_trials,
      "evaluation.completed_trial_count" => experiment.completed_trials,
      "evaluation.max_attempts" => experiment.max_attempts,
      "graph.id" => graph.id,
      "graph.revision_id" => graph.revision_id
    })
  end

  defp set_graph_span_attributes(graph) do
    Tracer.set_attributes(
      compact_attributes(%{"graph.id" => graph.id, "graph.revision_id" => graph.revision_id})
    )

    :ok
  end

  defp set_evaluation_span_status({:ok, %{status: "completed"}}) do
    Tracer.set_attributes(%{"evaluation.status" => "completed"})
    Tracer.set_status(OpenTelemetry.status(:ok))
  end

  defp set_evaluation_span_status(_result) do
    Tracer.set_attributes(%{"evaluation.status" => "failed"})
    Tracer.set_status(OpenTelemetry.status(:error))
  end

  defp set_plan_span_status({:ok, %OptimizationRun{} = plan}) do
    Tracer.set_attributes(%{
      "evaluation.plan_id" => plan.id,
      "evaluation.plan.status" => plan.status
    })

    Tracer.set_status(OpenTelemetry.status(:ok))
  end

  defp set_plan_span_status(_result), do: Tracer.set_status(OpenTelemetry.status(:error))

  defp log_evaluation_started(run) do
    Logger.debug("Evaluation started",
      event: "evaluation.run.started",
      evaluation_id: run.id,
      evaluation_run_id: run.id,
      correlation_id: run.id,
      graph_revision_id: run.source_graph_revision_id,
      manifest_id: manifest_value(run, "id"),
      plan_count: plan_count(run),
      trial_count: trial_count(run),
      evaluation_run: run
    )
  end

  defp log_evaluation_result(run, {:ok, %{status: "completed"} = completed}, runtime_ms) do
    Logger.debug("Evaluation completed",
      event: "evaluation.run.completed",
      evaluation_id: completed.id || run.id,
      evaluation_run_id: completed.id || run.id,
      correlation_id: run.id,
      graph_revision_id: run.source_graph_revision_id,
      manifest_id: manifest_value(run, "id"),
      plan_count: plan_count(run),
      trial_count: trial_count(run),
      runtime_ms: runtime_ms,
      evaluation_run: completed
    )
  end

  defp log_evaluation_result(
         _run,
         {:ok, %{status: "failed", failure_reason: reason} = failed},
         runtime_ms
       ) do
    log_evaluation_failed(failed, reason, runtime_ms)
  end

  defp log_evaluation_result(run, {:error, reason}, runtime_ms) do
    log_evaluation_failed(run, reason, runtime_ms)
  end

  defp log_evaluation_result(run, result, runtime_ms) do
    log_evaluation_failed(run, {:unexpected_result, result}, runtime_ms)
  end

  defp log_evaluation_failed(run, reason, runtime_ms) do
    Logger.error("Evaluation failed",
      event: "evaluation.run.failed",
      evaluation_id: run.id,
      evaluation_run_id: run.id,
      correlation_id: run.id,
      graph_revision_id: run.source_graph_revision_id,
      manifest_id: manifest_value(run, "id"),
      reason: reason,
      runtime_ms: runtime_ms,
      evaluation_run: run
    )
  end

  defp log_plan_started(run, graph, model_variant, strategy, budget, selection_seed) do
    model_variant = ModelVariant.to_wire(model_variant)

    Logger.debug("Evaluation plan started",
      event: "evaluation.plan.started",
      evaluation_id: run.id,
      evaluation_run_id: run.id,
      correlation_id: run.id,
      model_variant: model_variant,
      strategy: strategy,
      requested_budget: budget,
      selection_seed: selection_seed,
      evaluation_run: run,
      graph: graph
    )
  end

  defp log_plan_result(
         run,
         {:ok, %OptimizationRun{} = plan},
         model_variant,
         strategy,
         budget,
         selection_seed,
         runtime_ms,
         graph
       ) do
    model_variant = ModelVariant.to_wire(model_variant)

    Logger.debug("Evaluation plan completed",
      event: "evaluation.plan.completed",
      evaluation_id: run.id,
      evaluation_run_id: run.id,
      correlation_id: run.id,
      plan_id: plan.id,
      model_variant: model_variant,
      strategy: strategy,
      requested_budget: budget,
      selection_seed: selection_seed,
      status: plan.status,
      runtime_ms: runtime_ms,
      evaluation_run: run,
      optimization_run: plan,
      graph: graph
    )
  end

  defp log_plan_result(
         run,
         {:error, reason},
         model_variant,
         strategy,
         budget,
         selection_seed,
         runtime_ms,
         graph
       ) do
    log_plan_failed(
      run,
      model_variant,
      strategy,
      budget,
      selection_seed,
      reason,
      runtime_ms,
      graph
    )
  end

  defp log_plan_result(
         run,
         result,
         model_variant,
         strategy,
         budget,
         selection_seed,
         runtime_ms,
         graph
       ) do
    log_plan_failed(
      run,
      model_variant,
      strategy,
      budget,
      selection_seed,
      {:unexpected_result, result},
      runtime_ms,
      graph
    )
  end

  defp log_plan_failed(
         run,
         model_variant,
         strategy,
         budget,
         selection_seed,
         reason,
         runtime_ms,
         graph
       ) do
    model_variant = ModelVariant.to_wire(model_variant)

    Logger.error("Evaluation plan failed",
      event: "evaluation.plan.failed",
      evaluation_id: run.id,
      evaluation_run_id: run.id,
      correlation_id: run.id,
      model_variant: model_variant,
      strategy: strategy,
      requested_budget: budget,
      selection_seed: selection_seed,
      reason: reason,
      runtime_ms: runtime_ms,
      evaluation_run: run,
      graph: graph
    )
  end

  defp log_experiment_started(experiment, graph) do
    Logger.debug("Evaluation experiment started",
      event: "evaluation.experiment.started",
      evaluation_id: experiment.evaluation_run_id,
      evaluation_run_id: experiment.evaluation_run_id,
      correlation_id: experiment.evaluation_run_id,
      experiment_id: experiment.id,
      plan_id: experiment.optimization_run_id,
      experiment_type: experiment_type(experiment),
      graph_id: graph.id,
      graph_revision_id: graph.revision_id,
      trial_count: experiment.total_trials,
      completed_trial_count: experiment.completed_trials,
      experiment: experiment,
      graph: graph
    )
  end

  defp log_experiment_result(experiment, graph, runtime_ms) do
    Logger.debug("Evaluation experiment completed",
      event: "evaluation.experiment.completed",
      evaluation_id: experiment.evaluation_run_id,
      evaluation_run_id: experiment.evaluation_run_id,
      correlation_id: experiment.evaluation_run_id,
      experiment_id: experiment.id,
      plan_id: experiment.optimization_run_id,
      experiment_type: experiment_type(experiment),
      graph_id: graph.id,
      graph_revision_id: graph.revision_id,
      trial_count: experiment.total_trials,
      runtime_ms: runtime_ms,
      experiment: experiment,
      graph: graph
    )
  end

  defp log_experiment_failed(experiment, graph, reason, runtime_ms) do
    Logger.error("Evaluation experiment failed",
      event: "evaluation.experiment.failed",
      evaluation_id: experiment.evaluation_run_id,
      evaluation_run_id: experiment.evaluation_run_id,
      correlation_id: experiment.evaluation_run_id,
      experiment_id: experiment.id,
      plan_id: experiment.optimization_run_id,
      experiment_type: experiment_type(experiment),
      graph_id: graph.id,
      graph_revision_id: graph.revision_id,
      reason: reason,
      runtime_ms: runtime_ms,
      experiment: experiment,
      graph: graph
    )
  end

  defp experiment_type(%Experiment{optimization_run_id: nil}), do: "baseline"
  defp experiment_type(%Experiment{}), do: "post_defense"

  defp compact_attributes(attributes),
    do: Map.reject(attributes, fn {_key, value} -> is_nil(value) end)

  defp resolved_manifest(%{resolved_manifest: manifest}) when is_map(manifest), do: manifest
  defp resolved_manifest(_run), do: %{}

  defp manifest_value(run, key), do: Map.get(resolved_manifest(run), key)

  defp plan_count(run) do
    manifest = resolved_manifest(run)

    case Map.get(manifest, "strategy_runs") do
      strategy_runs when is_list(strategy_runs) ->
        Enum.reduce(strategy_runs, 0, fn run, count ->
          count + length(run["selection_seeds"] || [])
        end)

      _ ->
        0
    end
  end

  defp trial_count(run) do
    case get_in(resolved_manifest(run), ["evaluation", "trials"]) do
      trials when is_integer(trials) -> trials
      _ -> 0
    end
  end

  defp load_source(revision_id) do
    case Graphs.load_revision(revision_id) do
      %Graph{} = graph ->
        {:ok, graph}

      nil ->
        {:error, "source graph revision not found"}

      {:error, _reason} ->
        {:error, "source graph revision is invalid"}
    end
  end

  defp build_schedule(run) do
    manifest = run.resolved_manifest
    entry_host_id = get_in(manifest, ["attacker", "entry_host", "value"])
    {:ok, SeedSchedule.build(manifest, entry_host_id)}
  end

  defp select_plans(run, graph, schedule) do
    keys = PlanPreview.plans(run.resolved_manifest)
    plan_count = length(keys)
    total = progress_total(run)

    plans =
      Enum.reduce_while(keys, {:ok, []}, fn plan, {:ok, acc} ->
        case select_plan(run, graph, schedule, plan) do
          {:ok, optimization_run} ->
            selected = length(acc) + 1

            emit_progress(
              run.id,
              graph,
              selected,
              total,
              plan_selected_detail(plan, selected, plan_count)
            )

            {:cont, {:ok, [optimization_run | acc]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case plans do
      {:ok, runs} -> {:ok, Enum.reverse(runs)}
      error -> error
    end
  end

  defp plan_selected_detail(
         {model_variant, strategy, budget, selection_seed},
         selected,
         plan_count
       ) do
    "Selected plan #{selected} of #{plan_count}: #{ModelVariant.to_wire(model_variant)}/#{strategy} (budget #{budget}, seed #{selection_seed})"
  end

  defp select_plan(run, graph, schedule, {model_variant, strategy, budget, selection_seed}) do
    Tracer.with_span "evaluation.plan",
      attributes:
        plan_span_attributes(run, graph, model_variant, strategy, budget, selection_seed) do
      started_at = System.monotonic_time()
      log_plan_started(run, graph, model_variant, strategy, budget, selection_seed)

      try do
        result =
          select_plan_without_span(
            run,
            graph,
            schedule,
            model_variant,
            strategy,
            budget,
            selection_seed
          )

        set_plan_span_status(result)

        log_plan_result(
          run,
          result,
          model_variant,
          strategy,
          budget,
          selection_seed,
          Observability.duration_ms(started_at),
          graph
        )

        result
      rescue
        error ->
          Tracer.record_exception(error, __STACKTRACE__)
          Tracer.set_status(OpenTelemetry.status(:error))

          log_plan_failed(
            run,
            model_variant,
            strategy,
            budget,
            selection_seed,
            error,
            Observability.duration_ms(started_at),
            graph
          )

          reraise error, __STACKTRACE__
      end
    end
  end

  defp select_plan_without_span(
         run,
         graph,
         schedule,
         model_variant,
         strategy,
         budget,
         selection_seed
       ) do
    with {:ok, model} <- model_settings(run, model_variant) do
      case existing_plan(run.id, model_variant, strategy, budget, selection_seed) do
        %OptimizationRun{status: "completed"} = existing ->
          {:ok, existing}

        %OptimizationRun{} = existing ->
          resume_plan(existing, graph, schedule, strategy, budget, selection_seed, model)

        nil ->
          run_plan(run, graph, schedule, model_variant, strategy, budget, selection_seed, model)
      end
    end
  end

  defp run_plan(run, graph, schedule, model_variant, strategy, budget, selection_seed, model) do
    with {:ok, strategy_struct} <-
           build_strategy(strategy, graph, schedule, selection_seed, model),
         {:ok, optimization_run} <-
           create_optimization_run(
             run,
             model_variant,
             strategy,
             budget,
             selection_seed,
             strategy_struct
           ) do
      execute_optimization(graph, optimization_run, strategy_struct, budget, model)
    end
  end

  defp resume_plan(optimization_run, graph, schedule, strategy, budget, selection_seed, model) do
    case OptimizationRuns.resume_or_load(optimization_run.id) do
      {:ok, %OptimizationRun{status: "completed"} = completed} ->
        {:ok, completed}

      {:ok, running} ->
        with {:ok, strategy_struct} <-
               build_strategy(strategy, graph, schedule, selection_seed, model) do
          execute_optimization(graph, running, strategy_struct, budget, model)
        end

      error ->
        error
    end
  end

  defp create_optimization_run(
         run,
         model_variant,
         strategy,
         budget,
         selection_seed,
         strategy_struct
       ) do
    OptimizationRun.new(
      graph_revision_id: run.source_graph_revision_id,
      evaluation_run_id: run.id,
      model_variant: model_variant,
      strategy: strategy,
      requested_budget: budget,
      seed: strategy_struct.seed,
      selection_seed: selection_seed,
      simulation_config: simulation_config(strategy_struct)
    )
    |> OptimizationRuns.create()
  end

  defp execute_optimization(graph, optimization_run, strategy_struct, budget, model) do
    {elapsed_us, result} =
      :timer.tc(fn ->
        Optimizer.apply(graph, strategy_struct, budget,
          require_pre_attack_feasibility: model.require_pre_attack_feasibility
        )
      end)

    Graphs.append_optimization(result.graph, fn persisted ->
      OptimizationRuns.complete(optimization_run, %{
        actions: Enum.map(result.actions, &OptimizationAction.from_domain/1),
        used_budget: result.budget_used,
        runtime_ms: div(elapsed_us, 1000),
        output_graph_revision_id: persisted.revision_id
      })
    end)
  end

  defp run_experiments(run, graph, schedule, plans) do
    plan_count = length(plans)
    total = progress_total(run)

    with :ok <- run_baseline(run, graph, schedule, plan_count, total) do
      run_post_defense_experiments(run, schedule, plans, plan_count, total)
    end
  end

  defp run_post_defense_experiments(run, schedule, plans, plan_count, total) do
    Enum.reduce_while(Enum.with_index(plans, 1), :ok, fn {optimization_run, index}, :ok ->
      run_post_defense_step(run, schedule, optimization_run, plan_count, index, total)
    end)
  end

  defp run_post_defense_step(run, schedule, optimization_run, plan_count, index, total) do
    case run_post_defense(run, schedule, optimization_run, plan_count, index, total) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp run_baseline(run, graph, schedule, plan_count, total) do
    case existing_experiment(run.id, nil) do
      %Experiment{status: "completed"} ->
        :ok

      %Experiment{} = experiment ->
        resume_experiment(experiment, plan_count, total, "Baseline attack trials")

      nil ->
        create_and_run_experiment(
          run,
          graph,
          schedule,
          nil,
          plan_count,
          total,
          "Baseline attack trials"
        )
    end
  end

  defp run_post_defense(run, schedule, optimization_run, plan_count, index, total) do
    label = "Post-defense attack trials (plan #{index} of #{plan_count})"

    case existing_experiment(run.id, optimization_run.id) do
      %Experiment{status: "completed"} ->
        :ok

      %Experiment{} = experiment ->
        resume_experiment(experiment, plan_count, total, label)

      nil ->
        with {:ok, output_graph} <- load_source(optimization_run.output_graph_revision_id) do
          create_and_run_experiment(
            run,
            output_graph,
            schedule,
            optimization_run.id,
            plan_count,
            total,
            label
          )
        end
    end
  end

  defp create_and_run_experiment(
         run,
         graph,
         schedule,
         optimization_run_id,
         plan_count,
         total,
         label
       ) do
    experiment =
      Experiment.new(
        graph_revision_id: graph.revision_id,
        evaluation_run_id: run.id,
        optimization_run_id: optimization_run_id,
        master_seed: schedule.attack_evaluation_seed,
        iteration_count: 1,
        max_attempts: get_in(run.resolved_manifest, ["attacker", "max_attempts"]),
        total_trials: get_in(run.resolved_manifest, ["evaluation", "trials"]),
        initial_foothold_node_id: schedule.entry_host_id
      )

    with {:ok, experiment} <- Experiments.create(experiment) do
      base = progress_base(run.id, plan_count, experiment)
      run_experiment(experiment, graph, base, total, label)
    end
  end

  defp resume_experiment(experiment, plan_count, total, label) do
    case Experiments.resume_or_load(experiment.id) do
      {:ok, %Experiment{status: "completed"} = _} ->
        :ok

      {:ok, experiment} ->
        with {:ok, graph} <- load_source(experiment.graph_revision_id) do
          base = progress_base(experiment.evaluation_run_id, plan_count, experiment)
          run_experiment(experiment, graph, base, total, label)
        end

      error ->
        error
    end
  end

  defp progress_base(evaluation_run_id, plan_count, experiment) do
    plan_count + persisted_trials(evaluation_run_id) - experiment.completed_trials
  end

  defp persisted_trials(evaluation_run_id) do
    import Ecto.Query

    Experiment
    |> where([experiment], experiment.evaluation_run_id == ^evaluation_run_id)
    |> select([experiment], coalesce(sum(experiment.completed_trials), 0))
    |> NetworkDefense.Repo.one()
  end

  defp run_experiment(experiment, graph, base, total, label) do
    Tracer.with_span "evaluation.experiment",
      attributes: experiment_span_attributes(experiment, graph) do
      started_at = System.monotonic_time()
      log_experiment_started(experiment, graph)

      try do
        completed = execute_experiment(experiment, graph, base, total, label)
        Tracer.set_status(OpenTelemetry.status(:ok))
        log_experiment_result(completed, graph, Observability.duration_ms(started_at))
        :ok
      rescue
        error ->
          Tracer.record_exception(error, __STACKTRACE__)
          Tracer.set_status(OpenTelemetry.status(:error))

          failed_experiment = failed_experiment(experiment)

          log_experiment_failed(
            failed_experiment,
            graph,
            error,
            Observability.duration_ms(started_at)
          )

          reraise error, __STACKTRACE__
      end
    end
  end

  defp execute_experiment(experiment, graph, base, total, label) do
    run_id = experiment.evaluation_run_id

    Simulations.run_batches(graph, run_id, experiment, fn saved ->
      emit_progress(
        run_id,
        graph,
        base + saved.completed_trials,
        total,
        "#{label}: #{saved.completed_trials} of #{saved.total_trials}"
      )
    end)
  end

  defp progress_total(run) do
    plan_count = run.resolved_manifest |> PlanPreview.plans() |> length()
    trials = get_in(run.resolved_manifest, ["evaluation", "trials"])
    plan_count + (plan_count + 1) * trials
  end

  defp emit_progress(run_id, graph, completed, total, detail) do
    Evaluation.broadcast_progress(run_id, graph, completed, total, detail)
  end

  defp build_strategy(strategy, graph, schedule, selection_seed, model) do
    case strategy do
      "null" ->
        {:ok, %NullStrategy{}}

      "random" ->
        {:ok, %RandomStrategy{seed: selection_seed}}

      "cvss" ->
        {:ok, %CvssStrategy{}}

      "topology_segmentation" ->
        build_topology_strategy(graph, schedule)

      "simulation_informed" ->
        build_simulation_strategy(
          SimulationInformedStrategy,
          graph,
          schedule,
          selection_seed,
          model
        )

      "simulated_annealing" ->
        build_simulation_strategy(
          SimulatedAnnealingStrategy,
          graph,
          schedule,
          selection_seed,
          model
        )

      other ->
        {:error, "unknown strategy #{other}"}
    end
  end

  defp build_simulation_strategy(module, graph, schedule, selection_seed, model) do
    params = %{
      simulation_params: %{
        monte_carlo_trials: schedule.optimizer_trials,
        iterations_per_run: schedule.optimizer_iterations,
        initial_foothold_node_id: schedule.entry_host_id,
        seed: SeedSchedule.optimizer_simulation_seed(selection_seed),
        generate_seed: false,
        max_attempts: schedule.max_attempts
      },
      model: model
    }

    SimulationStrategy.new(module, graph, params)
  end

  defp build_topology_strategy(graph, schedule) do
    params = %{simulation_params: %{initial_foothold_node_id: schedule.entry_host_id}}

    TopologySegmentationStrategy.new(graph, params)
  end

  defp simulation_config(%{seed: seed}) when is_integer(seed), do: %{seed: seed}
  defp simulation_config(_strategy), do: nil

  defp model_settings(run, model_variant) do
    if model_variant in manifest_variants(run.resolved_manifest) do
      {:ok, ModelVariant.definition(model_variant)}
    else
      {:error, "unknown model variant #{ModelVariant.to_wire(model_variant)}"}
    end
  end

  defp model_variant!(wire) do
    {:ok, variant} = ModelVariant.from_wire(wire)
    variant
  end

  defp manifest_variants(manifest) do
    manifest
    |> Map.get("model_variants", [])
    |> Enum.map(&model_variant!(&1["id"]))
  end

  defp existing_plan(evaluation_run_id, model_variant, strategy, budget, selection_seed) do
    import Ecto.Query

    OptimizationRun
    |> where(
      [run],
      run.evaluation_run_id == ^evaluation_run_id and
        run.model_variant == ^model_variant and
        run.strategy == ^strategy and
        run.requested_budget == ^budget and
        run.selection_seed == ^selection_seed
    )
    |> NetworkDefense.Repo.one()
  end

  defp existing_experiment(evaluation_run_id, nil) do
    import Ecto.Query

    Experiment
    |> where(
      [experiment],
      experiment.evaluation_run_id == ^evaluation_run_id and
        is_nil(experiment.optimization_run_id)
    )
    |> NetworkDefense.Repo.one()
  end

  defp existing_experiment(evaluation_run_id, optimization_run_id) do
    import Ecto.Query

    Experiment
    |> where(
      [experiment],
      experiment.evaluation_run_id == ^evaluation_run_id and
        experiment.optimization_run_id == ^optimization_run_id
    )
    |> NetworkDefense.Repo.one()
  end

  defp failed_run(%{id: id} = run, reason) when is_binary(id) do
    case EvaluationRuns.fail(run, reason) do
      {:ok, failed} -> failed
      {:error, _changeset} -> %{run | status: "failed", failure_reason: reason}
    end
  rescue
    Ecto.StaleEntryError -> %{run | status: "failed", failure_reason: reason}
  end

  defp failed_run(run, reason), do: %{run | status: "failed", failure_reason: reason}

  defp fail(run, reason), do: {:ok, failed_run(run, reason)}

  defp failed_experiment(%Experiment{id: id} = experiment) do
    Experiments.fail(id)
    Experiments.get(id) || %{experiment | status: "failed"}
  end
end
