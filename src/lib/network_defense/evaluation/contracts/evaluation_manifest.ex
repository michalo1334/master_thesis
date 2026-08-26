defmodule NetworkDefense.Evaluation.Contracts.EvaluationManifest do
  @moduledoc "Validates evaluation manifests before persistence and execution."

  require Logger
  alias NetworkDefense.Evaluation.PlanPreview
  alias NetworkDefense.Optimization.{ModelVariant, SimulationObjective}
  alias NetworkDefense.Topology.EnterpriseTopology

  @schema_version 3
  @strategies ~w(null random cvss topology_segmentation simulation_informed simulated_annealing)
  @cross_model_strategies ~w(simulation_informed simulated_annealing)
  @corrections ~w(holm none)
  @outcomes ~w(blast_radius mission_impact)
  @type error :: %{path: String.t(), message: String.t()}

  @spec parse(String.t()) :: {:ok, map()} | {:error, [error()]}
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, manifest} -> validate(manifest)
      {:error, _} -> error("$", "invalid JSON")
    end
  end

  @spec validate(map()) :: {:ok, map()} | {:error, [error()]}
  def validate(manifest) when is_map(manifest) do
    unknown(
      manifest,
      "$",
      ~w(schema_version model_version model_variants id source attacker strategy_runs analysis evaluation)
    )

    with :ok <-
           fields(manifest, nil, [
             {"schema_version", &(&1 == @schema_version), "must be 3"},
             {"model_version", &text?/1, "must be a non-empty string"},
             {"id", &text?/1, "must be a non-empty string"}
           ]),
         :ok <- model_variants(manifest),
         :ok <- source(manifest),
         :ok <- attacker(manifest),
         :ok <- strategy_runs(manifest),
         :ok <- analysis(manifest),
         :ok <- evaluation(manifest) do
      {:ok, manifest}
    end
  end

  def validate(_), do: error("$", "manifest must be a JSON object")

  defp source(%{"source" => %{"type" => "topology"} = source}) do
    unknown(source, "source", ~w(type generator hosts seed))

    with :ok <-
           field(
             source,
             "generator",
             &(&1 == "enterprise"),
             "must be a known generator",
             "source"
           ),
         :ok <- hosts(source) do
      field(
        source,
        "seed",
        &(is_integer(&1) and &1 >= 0),
        "must be a non-negative integer",
        "source"
      )
    end
  end

  defp source(%{"source" => %{"type" => "graph_revision"} = source}) do
    unknown(source, "source", ~w(type graph_revision_id))
    field(source, "graph_revision_id", &uuid?/1, "must be a valid UUID", "source")
  end

  defp source(%{"source" => %{} = source}) do
    unknown(source, "source", ~w(type generator hosts seed graph_revision_id))
    error("source.type", "must be \"topology\" or \"graph_revision\"")
  end

  defp source(_), do: error("source", "is required")

  defp hosts(source) do
    minimum = EnterpriseTopology.minimum_hosts()

    field(
      source,
      "hosts",
      &(is_integer(&1) and &1 >= minimum),
      "must meet the minimum host count",
      "source"
    )
  end

  defp attacker(%{"attacker" => %{"entry_host" => entry} = attacker} = manifest) do
    unknown(attacker, "attacker", ~w(entry_host max_attempts))
    if is_map(entry), do: unknown(entry, "attacker.entry_host", ~w(type value))

    with :ok <- entry_host(entry),
         :ok <-
           field(
             attacker,
             "max_attempts",
             &(is_integer(&1) and &1 > 0),
             "must be a positive integer",
             "attacker"
           ) do
      selector_compatibility(manifest)
    end
  end

  defp attacker(%{"attacker" => _}), do: error("attacker.entry_host", "is required")
  defp attacker(_), do: error("attacker", "is required")

  defp entry_host(%{"type" => "semantic_key", "value" => value})
       when is_binary(value) and value != "", do: :ok

  defp entry_host(%{"type" => "node_id", "value" => value}) when is_binary(value),
    do:
      field(%{"value" => value}, "value", &uuid?/1, "must be a valid UUID", "attacker.entry_host")

  defp entry_host(%{"type" => type}) when is_binary(type),
    do: error("attacker.entry_host.type", "unknown selector type")

  defp entry_host(_), do: error("attacker.entry_host", "must be an object with a type and value")

  defp selector_compatibility(%{
         "source" => %{"type" => source},
         "attacker" => %{"entry_host" => %{"type" => selector}}
       })
       when source == "topology" and selector == "semantic_key", do: :ok

  defp selector_compatibility(%{
         "source" => %{"type" => source},
         "attacker" => %{"entry_host" => %{"type" => selector}}
       })
       when source == "graph_revision" and selector == "node_id", do: :ok

  defp selector_compatibility(_),
    do: error("attacker.entry_host.type", "source and selector types are incompatible")

  defp model_variants(%{"model_variants" => variants})
       when is_list(variants) and variants != [] do
    ids = Enum.map(variants, fn variant -> if is_map(variant), do: variant["id"], else: nil end)

    with :ok <-
           each(Enum.with_index(variants), fn {variant, index} ->
             model_variant(variant, index)
           end) do
      unique(ids, "model_variants", "must contain unique variant ids")
    end
  end

  defp model_variants(%{"model_variants" => []}), do: error("model_variants", "must not be empty")
  defp model_variants(%{"model_variants" => _}), do: error("model_variants", "must be a list")
  defp model_variants(_), do: error("model_variants", "is required")

  defp model_variant(variant, index) when is_map(variant) do
    path = "model_variants.#{index}"
    unknown(variant, path, ~w(id objective require_pre_attack_feasibility))

    with :ok <- field(variant, "id", &text?/1, "must be a non-empty string", path),
         {:ok, model_variant} <- model_variant_id(variant["id"], path),
         :ok <- field(variant, "objective", &text?/1, "must be a known objective", path),
         {:ok, objective} <- model_objective(variant["objective"], path),
         :ok <-
           field(
             variant,
             "require_pre_attack_feasibility",
             &is_boolean/1,
             "must be a boolean",
             path
           ) do
      canonical = ModelVariant.definition(model_variant)

      cond do
        objective != canonical.objective ->
          error("#{path}.objective", "must match the canonical model variant objective")

        variant["require_pre_attack_feasibility"] != canonical.require_pre_attack_feasibility ->
          error(
            "#{path}.require_pre_attack_feasibility",
            "must match the canonical model variant feasibility rule"
          )

        true ->
          :ok
      end
    end
  end

  defp model_variant(_, _), do: error("model_variants", "each variant must be an object")

  defp model_variant_id(wire, path) do
    case ModelVariant.from_wire(wire) do
      {:ok, variant} -> {:ok, variant}
      :error -> error("#{path}.id", "must be a known model variant")
    end
  end

  defp model_objective(wire, path) do
    case SimulationObjective.from_wire(wire) do
      {:ok, objective} -> {:ok, objective}
      :error -> error("#{path}.objective", "must be a known objective")
    end
  end

  defp strategy_runs(%{"strategy_runs" => runs} = manifest) when is_list(runs) and runs != [] do
    keys =
      Enum.map(runs, fn run ->
        if is_map(run), do: {run["model_variant"], run["strategy"], run["budget"]}, else: nil
      end)

    with :ok <- each(Enum.with_index(runs), fn {run, index} -> strategy_run(run, index) end),
         :ok <- declared_variant_references(runs, manifest) do
      unique(
        keys,
        "strategy_runs",
        "must contain unique model variant, strategy, and budget plans"
      )
    end
  end

  defp strategy_runs(%{"strategy_runs" => []}), do: error("strategy_runs", "must not be empty")
  defp strategy_runs(%{"strategy_runs" => _}), do: error("strategy_runs", "must be a list")
  defp strategy_runs(_), do: error("strategy_runs", "is required")

  defp strategy_run(run, index) when is_map(run) do
    path = "strategy_runs.#{index}"
    unknown(run, path, ~w(model_variant strategy budget selection_seeds))

    with :ok <-
           fields(run, path, [
             {"model_variant", &text?/1, "must be a non-empty string"},
             {"strategy", &(&1 in @strategies), "must be a known strategy"},
             {"budget", &(is_integer(&1) and &1 > 0), "must be a positive integer"}
           ]) do
      seeds(run, path)
    end
  end

  defp strategy_run(_, _), do: error("strategy_runs", "each run must be an object")

  defp declared_variant_references(runs, manifest) do
    ids = declared_variant_ids(manifest)

    runs
    |> Enum.find_index(fn run ->
      not (is_map(run) and MapSet.member?(ids, run["model_variant"]))
    end)
    |> case do
      nil -> :ok
      index -> error("strategy_runs.#{index}.model_variant", "must be a declared model variant")
    end
  end

  defp declared_variant_ids(%{"model_variants" => variants}) when is_list(variants),
    do: MapSet.new(variants, fn variant -> if is_map(variant), do: variant["id"], else: nil end)

  defp declared_variant_ids(_), do: MapSet.new()

  defp seeds(run, path) do
    case run["selection_seeds"] do
      seeds when is_list(seeds) and seeds != [] ->
        if Enum.all?(seeds, &(is_integer(&1) and &1 >= 0)) and
             length(Enum.uniq(seeds)) == length(seeds),
           do: :ok,
           else: error("#{path}.selection_seeds", "must be unique non-negative integers")

      [] ->
        error("#{path}.selection_seeds", "must not be empty")

      _ ->
        error("#{path}.selection_seeds", "must be a list")
    end
  end

  defp analysis(%{"analysis" => %{} = analysis} = manifest) do
    unknown(
      analysis,
      "analysis",
      ~w(primary_comparisons confidence_level bootstrap_resamples permutation_resamples multiplicity_correction seed pilot)
    )

    with :ok <- comparisons(analysis["primary_comparisons"], manifest),
         :ok <-
           fields(analysis, "analysis", [
             {"confidence_level", &(is_number(&1) and &1 > 0 and &1 < 1),
              "must be strictly between 0 and 1"},
             {"bootstrap_resamples", &(is_integer(&1) and &1 > 0), "must be a positive integer"},
             {"permutation_resamples", &(is_integer(&1) and &1 > 0),
              "must be a positive integer"},
             {"multiplicity_correction", &(&1 in @corrections), "must be \"holm\" or \"none\""},
             {"seed", &(is_integer(&1) and &1 >= 0), "must be a non-negative integer"}
           ]) do
      pilot(analysis["pilot"])
    end
  end

  defp analysis(_), do: error("analysis", "is required")

  defp comparisons(comparisons, manifest) when is_list(comparisons) and comparisons != [] do
    keys =
      Enum.map(comparisons, fn comparison ->
        if is_map(comparison),
          do:
            Map.take(
              comparison,
              ~w(strategy baseline model_variant baseline_model_variant budget outcome)
            ),
          else: nil
      end)

    with :ok <-
           each(Enum.with_index(comparisons), fn {comparison, index} ->
             comparison(comparison, manifest, index)
           end),
         do: unique(keys, "analysis.primary_comparisons", "must not contain duplicates")
  end

  defp comparisons(_, _), do: error("analysis.primary_comparisons", "must be a non-empty list")

  defp comparison(comparison, manifest, index) when is_map(comparison) do
    path = "analysis.primary_comparisons.#{index}"

    unknown(
      comparison,
      path,
      ~w(strategy baseline model_variant baseline_model_variant budget outcome)
    )

    strategy = comparison["strategy"]
    baseline = comparison["baseline"]
    variant = comparison["model_variant"]
    baseline_variant = comparison["baseline_model_variant"]
    budget = comparison["budget"]

    with :ok <-
           fields(comparison, path, [
             {"strategy", &(&1 in @strategies), "must be a declared strategy"},
             {"baseline", &(&1 in @strategies), "must be a declared strategy"},
             {"model_variant", &text?/1, "must be a non-empty string"},
             {"baseline_model_variant", &text?/1, "must be a non-empty string"},
             {"budget", &(is_integer(&1) and &1 > 0), "must be a positive integer"},
             {"outcome", &(&1 in @outcomes), "must be a valid outcome"}
           ]),
         :ok <- distinct_sides(path, strategy, baseline, variant, baseline_variant),
         :ok <- declared_plan(manifest, "#{path}.strategy", variant, strategy, budget),
         :ok <- declared_plan(manifest, "#{path}.baseline", baseline_variant, baseline, budget),
         :ok <- cross_model_strategies(path, variant, baseline_variant, strategy, baseline),
         :ok <- confounding_guard(path, variant, baseline_variant) do
      matching_seeds(manifest, path, variant, baseline_variant, strategy, baseline, budget)
    end
  end

  defp comparison(_, _, _),
    do: error("analysis.primary_comparisons", "each comparison must be an object")

  defp distinct_sides(path, strategy, baseline, variant, baseline_variant) do
    if strategy == baseline and variant == baseline_variant,
      do: error(path, "comparison sides must differ"),
      else: :ok
  end

  defp declared_plan(manifest, path, variant, strategy, budget) do
    if PlanPreview.declared?(manifest, variant, strategy, budget),
      do: :ok,
      else: error(path, "model variant, strategy, and budget must be declared")
  end

  defp cross_model_strategies(path, variant, baseline_variant, strategy, baseline) do
    cross_model? = variant != baseline_variant
    allowed? = strategy in @cross_model_strategies and baseline in @cross_model_strategies

    if cross_model? and not allowed?,
      do:
        error(
          path,
          "cross-model comparisons require simulation_informed or simulated_annealing strategies"
        ),
      else: :ok
  end

  defp confounding_guard(path, variant, baseline_variant) when variant != baseline_variant do
    with {:ok, model_variant} <- ModelVariant.from_wire(variant),
         {:ok, baseline_model_variant} <- ModelVariant.from_wire(baseline_variant) do
      variant_definition = ModelVariant.definition(model_variant)
      baseline_definition = ModelVariant.definition(baseline_model_variant)

      objective_differs? = variant_definition.objective != baseline_definition.objective

      feasibility_differs? =
        variant_definition.require_pre_attack_feasibility !=
          baseline_definition.require_pre_attack_feasibility

      if objective_differs? and feasibility_differs? do
        error(
          path,
          "cross-model comparisons must vary only one of objective or feasibility"
        )
      else
        :ok
      end
    else
      :error -> error(path, "cross-model comparisons must use known model variants")
    end
  end

  defp confounding_guard(_, _, _), do: :ok

  defp matching_seeds(manifest, path, variant, baseline_variant, strategy, baseline, budget)
       when strategy == baseline and variant != baseline_variant do
    if PlanPreview.selection_seeds(manifest, variant, strategy, budget) ==
         PlanPreview.selection_seeds(manifest, baseline_variant, strategy, budget) do
      :ok
    else
      error(
        "#{path}.baseline_model_variant",
        "same-strategy comparisons must declare identical ordered selection seeds"
      )
    end
  end

  defp matching_seeds(_, _, _, _, _, _, _), do: :ok

  defp pilot(%{} = pilot) do
    unknown(pilot, "analysis.pilot", ~w(ci_half_width))

    field(
      pilot,
      "ci_half_width",
      &(is_number(&1) and &1 > 0),
      "must be a positive number",
      "analysis.pilot"
    )
  end

  defp pilot(_), do: error("analysis.pilot", "is required")

  defp evaluation(%{"evaluation" => %{} = evaluation}) do
    unknown(evaluation, "evaluation", ~w(trials seed optimizer_trials optimizer_iterations))

    with :ok <-
           fields(evaluation, "evaluation", [
             {"trials", &(is_integer(&1) and &1 > 0), "must be a positive integer"},
             {"seed", &(is_integer(&1) and &1 >= 0), "must be a non-negative integer"}
           ]),
         :ok <-
           optional_field(
             evaluation,
             "optimizer_trials",
             &(is_integer(&1) and &1 > 0),
             "must be a positive integer",
             "evaluation"
           ) do
      optional_field(
        evaluation,
        "optimizer_iterations",
        &(is_integer(&1) and &1 > 0),
        "must be a positive integer",
        "evaluation"
      )
    end
  end

  defp evaluation(_), do: error("evaluation", "is required")

  defp each(values, fun),
    do:
      Enum.reduce_while(values, :ok, fn value, :ok ->
        case fun.(value) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)

  defp unique(values, path, message),
    do: if(length(values) == length(Enum.uniq(values)), do: :ok, else: error(path, message))

  defp fields(map, prefix, definitions) do
    each(definitions, fn {key, predicate, message} ->
      if prefix,
        do: field(map, key, predicate, message, prefix),
        else: scalar(map, key, predicate, message)
    end)
  end

  defp scalar(map, key, predicate, message) do
    case Map.fetch(map, key) do
      {:ok, value} -> if(predicate.(value), do: :ok, else: error(key, message))
      :error -> error(key, "is required")
    end
  end

  defp field(map, key, predicate, message, prefix),
    do: scalar(map, key, predicate, message) |> path("#{prefix}.#{key}")

  defp optional_field(map, key, predicate, message, prefix) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        if predicate.(value),
          do: :ok,
          else: error("#{prefix}.#{key}", message)

      :error ->
        :ok
    end
  end

  defp path({:error, [%{path: _} = error]}, path), do: {:error, [%{error | path: path}]}
  defp path(:ok, _), do: :ok
  defp error(path, message), do: {:error, [%{path: path, message: message}]}
  defp text?(value), do: is_binary(value) and value != ""
  defp uuid?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp uuid?(_), do: false

  defp unknown(map, path, allowed) do
    Enum.each(Map.keys(map) -- allowed, &Logger.warning("#{path}.#{&1}"))
  end
end
