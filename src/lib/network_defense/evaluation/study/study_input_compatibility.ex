defmodule NetworkDefense.Evaluation.StudyInputCompatibility do
  @moduledoc """
  Derives the required evaluation-run input shape from a validated study
  specification and checks evaluation runs against it.

  The Python study loader rejects a bundle in
  `evaluation/analysis/src/network_defense_analysis/study.py` after it loads
  every tier. This module applies the same input checks before the dashboard
  exports a tier, so a user cannot map a run that the service will refuse. It
  mirrors these loader rules:

  - each tier manifest declares exactly one model variant;
  - every mapped tier uses the same model variant and the same analysis
    settings: `confidence_level`, `bootstrap_resamples`,
    `permutation_resamples`, and `seed`;
  - `multiplicity_correction` is `holm`;
  - each tier manifest's primary-comparison matrix equals the cross product of
    `expected_family.strategies`, `expected_family.budgets`,
    `expected_family.baseline`, and `expected_family.outcome`, with no
    duplicate comparison.

  The module also mirrors the loader's mode seed schedule enforcement. Pilot
  mode uses `pilot_seed_schedule` and analyze mode uses `final_seed_schedule`.
  Each mapped run's `evaluation.seed` must belong to the declared evaluation
  set, and every strategy-run selection seed must belong to the declared
  selection set. A complete preflight additionally requires the observed tier
  evaluation seeds to equal the declared evaluation set exactly, so one
  schedule cannot substitute for the other. Strategy runs generate one plan
  per declared selection seed, so the strategy-run check covers the exported
  plan selection seeds too.

  `shape/1` reads a validated specification. Values stay strings and numbers;
  the module never converts a source value to an atom.
  """

  alias NetworkDefense.Evaluation.EvaluationRun

  @correction "holm"

  @type mode :: :pilot | :final

  @type schedule :: %{selection: MapSet.t(integer()), evaluation: MapSet.t(integer())}

  @type shape :: %{
          strategies: [String.t()],
          baseline: String.t(),
          budgets: [integer()],
          outcome: String.t(),
          pairs: MapSet.t(),
          schedules: %{pilot: schedule(), final: schedule()}
        }

  @type settings :: %{
          confidence_level: number(),
          bootstrap_resamples: integer(),
          permutation_resamples: integer(),
          seed: integer()
        }

  @type requisites :: %{
          model_variant: String.t(),
          settings: settings(),
          pairs: MapSet.t(),
          evaluation_seed: non_neg_integer(),
          selection_seeds: [non_neg_integer()]
        }

  @doc """
  Derives the required input shape from a validated study specification.

  The rejection reason is always `:invalid_study_spec`; the authoritative
  specification validator reports the specific field errors.
  """
  @spec shape(term()) :: {:ok, shape()} | {:error, :invalid_study_spec}
  def shape(specification) do
    with {:ok, family} <- declared_family(specification),
         {:ok, schedules} <- declared_schedules(specification) do
      {:ok,
       family
       |> Map.put(:pairs, expected_pairs(family))
       |> Map.put(:schedules, schedules)}
    else
      :error -> {:error, :invalid_study_spec}
    end
  end

  @doc "Projects the derived shape back to the four declared family fields."
  @spec family(shape()) :: map()
  def family(%{strategies: strategies, baseline: baseline, budgets: budgets, outcome: outcome}) do
    %{
      "strategies" => strategies,
      "baseline" => baseline,
      "budgets" => budgets,
      "outcome" => outcome
    }
  end

  @doc "Builds one concise, human-readable required-input summary."
  @spec summary(shape()) :: String.t()
  def summary(%{strategies: strategies, baseline: baseline, budgets: budgets, outcome: outcome}) do
    "1 model variant · strategies: #{Enum.join(strategies, ", ")} · " <>
      "baseline: #{baseline} · budgets: #{Enum.join(budgets, ", ")} · outcome: #{outcome}"
  end

  @doc """
  Reports whether one evaluation run satisfies the required input shape.

  The run must declare exactly one model variant, a valid `holm` analysis
  configuration, and the exact expected primary-comparison matrix.
  """
  @spec compatible?(EvaluationRun.t() | term(), shape() | term()) :: boolean()
  def compatible?(%EvaluationRun{} = run, %{pairs: expected}) do
    case requisites(run) do
      {:ok, %{pairs: pairs}} -> MapSet.equal?(pairs, expected)
      {:error, _reason} -> false
    end
  end

  def compatible?(_run, _shape), do: false

  @doc """
  Reports whether one evaluation run satisfies the shape and the mode seed
  schedule.

  The run must pass `compatible?/2`, declare its evaluation seed inside the
  declared mode evaluation set, and keep every strategy-run selection seed
  inside the declared mode selection set. The picker uses this predicate, so a
  run that only fits the other mode never appears for a tier.
  """
  @spec mode_compatible?(EvaluationRun.t() | term(), shape() | term(), mode()) :: boolean()
  def mode_compatible?(%EvaluationRun{} = run, %{pairs: expected} = shape, mode)
      when mode in [:pilot, :final] do
    with {:ok, schedule} <- schedule(shape, mode),
         {:ok, requisites} <- requisites(run),
         true <- MapSet.equal?(requisites.pairs, expected),
         true <- MapSet.member?(schedule.evaluation, requisites.evaluation_seed),
         true <-
           Enum.all?(requisites.selection_seeds, &MapSet.member?(schedule.selection, &1)) do
      true
    else
      _mismatch -> false
    end
  end

  def mode_compatible?(_run, _shape, _mode), do: false

  @doc """
  Checks one run against its mode schedule and its persisted exported plans.

  The three-argument predicate remains useful for pure manifest validation.
  Study listing, preflight, and start call this form with the authoritative
  `optimization_runs.selection_seed` values that `plans.jsonl` exports.
  """
  @spec mode_compatible?(EvaluationRun.t() | term(), shape() | term(), mode(), term()) ::
          boolean()
  def mode_compatible?(%EvaluationRun{} = run, %{schedules: _schedules} = shape, mode, seeds)
      when mode in [:pilot, :final] and is_list(seeds) do
    mode_compatible?(run, shape, mode) and selection_seeds_match?(shape, mode, seeds)
  end

  def mode_compatible?(_run, _shape, _mode, _seeds), do: false

  @doc """
  Reports whether every run shares one model variant, one set of common
  analysis settings, and the declared mode evaluation set.

  Call this after `mode_compatible?/3` for each run. The observed tier
  evaluation seeds must equal the declared set exactly, so a mapping that
  leaves a declared seed unused or brings an undeclared seed fails. An empty
  list is not a valid mapping, so it returns `false`.
  """
  @spec consistent?([EvaluationRun.t()], shape(), mode()) :: boolean()
  def consistent?(runs, %{} = shape, mode) when is_list(runs) and mode in [:pilot, :final] do
    with {:ok, schedule} <- schedule(shape, mode),
         true <- runs |> Enum.map(&requisite_pair/1) |> Enum.uniq() |> one_shared_pair?(),
         {:ok, observed} <- observed_evaluation_seeds(runs) do
      MapSet.equal?(observed, schedule.evaluation)
    else
      _mismatch -> false
    end
  end

  def consistent?(_runs, _shape, _mode), do: false

  defp selection_seeds_match?(shape, mode, seeds) do
    with {:ok, schedule} <- schedule(shape, mode),
         true <- seeds != [],
         true <- Enum.all?(seeds, &(is_integer(&1) and &1 >= 0)),
         true <- Enum.all?(seeds, &MapSet.member?(schedule.selection, &1)) do
      true
    else
      _mismatch -> false
    end
  end

  # One run's evaluation seed and strategy-run selection seeds. Requisites
  # already rejects a manifest without either declaration, so the mode check
  # cannot hide a missing seed behind a default.
  defp observed_evaluation_seeds(runs) do
    runs
    |> Enum.reduce_while({:ok, MapSet.new()}, fn run, {:ok, acc} ->
      case requisites(run) do
        {:ok, %{evaluation_seed: seed}} -> {:cont, {:ok, MapSet.put(acc, seed)}}
        {:error, _reason} -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, seeds} -> {:ok, seeds}
      :error -> :error
    end
  end

  defp requisite_pair(run) do
    case requisites(run) do
      {:ok, %{model_variant: variant, settings: settings}} -> {variant, settings}
      {:error, _reason} -> :error
    end
  end

  defp one_shared_pair?([pair]), do: pair != :error
  defp one_shared_pair?(_pairs), do: false

  @spec requisites(EvaluationRun.t() | term()) ::
          {:ok, requisites()} | {:error, :incompatible_run}
  defp requisites(%EvaluationRun{resolved_manifest: %{} = manifest}) do
    with {:ok, variant} <- single_variant(manifest),
         {:ok, configuration} <- configuration(manifest),
         {:ok, settings} <- settings(configuration),
         {:ok, pairs} <- comparison_pairs(configuration),
         {:ok, evaluation_seed} <- evaluation_seed(manifest),
         {:ok, selection_seeds} <- selection_seeds(manifest) do
      {:ok,
       %{
         model_variant: variant,
         settings: settings,
         pairs: MapSet.new(pairs),
         evaluation_seed: evaluation_seed,
         selection_seeds: selection_seeds
       }}
    else
      _error -> {:error, :incompatible_run}
    end
  end

  defp requisites(_run), do: {:error, :incompatible_run}

  @spec schedule(shape() | term(), mode()) :: {:ok, schedule()} | :error
  defp schedule(%{schedules: %{} = schedules}, mode) when mode in [:pilot, :final],
    do: Map.fetch(schedules, mode)

  defp schedule(_shape, _mode), do: :error

  defp declared_schedules(%{} = specification) do
    with {:ok, pilot} <- declared_schedule(specification, "pilot_seed_schedule"),
         {:ok, final} <- declared_schedule(specification, "final_seed_schedule") do
      {:ok, %{pilot: pilot, final: final}}
    else
      _error -> :error
    end
  end

  defp declared_schedule(specification, name) do
    with %{} = declared <- Map.get(specification, name),
         {:ok, selection} <- seed_set(declared["selection"]),
         {:ok, evaluation} <- seed_set(declared["evaluation"]) do
      {:ok, %{selection: selection, evaluation: evaluation}}
    else
      _error -> :error
    end
  end

  defp seed_set(values) when is_list(values) do
    integers = Enum.map(values, &coerce_integer/1)

    if Enum.all?(integers, &(is_integer(&1) and &1 >= 0)) do
      {:ok, MapSet.new(integers)}
    else
      :error
    end
  end

  defp seed_set(_values), do: :error

  defp evaluation_seed(%{} = manifest) do
    with %{} = evaluation <- Map.get(manifest, "evaluation"),
         {:ok, seed} <- non_negative_integer(evaluation["seed"]) do
      {:ok, seed}
    else
      _error -> :error
    end
  end

  defp selection_seeds(%{} = manifest) do
    case Map.get(manifest, "strategy_runs") do
      [_first | _rest] = strategy_runs -> collect_selection_seeds(strategy_runs)
      _value -> :error
    end
  end

  defp collect_selection_seeds(strategy_runs) do
    Enum.reduce_while(strategy_runs, {:ok, []}, fn run, {:ok, acc} ->
      case strategy_run_seeds(run) do
        {:ok, seeds} -> {:cont, {:ok, acc ++ seeds}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp strategy_run_seeds(%{} = run) do
    case Map.get(run, "selection_seeds") do
      [_first | _rest] = seeds ->
        integers = Enum.map(seeds, &coerce_integer/1)

        if Enum.all?(integers, &(is_integer(&1) and &1 >= 0)), do: {:ok, integers}, else: :error

      _value ->
        :error
    end
  end

  defp strategy_run_seeds(_run), do: :error

  defp declared_family(%{} = specification) do
    with %{} = declared <- Map.get(specification, "expected_family"),
         {:ok, strategies} <- string_list(declared["strategies"]),
         {:ok, baseline} <- non_empty_string(declared["baseline"]),
         {:ok, budgets} <- integer_list(declared["budgets"]),
         {:ok, outcome} <- non_empty_string(declared["outcome"]) do
      {:ok, %{strategies: strategies, baseline: baseline, budgets: budgets, outcome: outcome}}
    else
      _error -> :error
    end
  end

  defp declared_family(_specification), do: :error

  defp expected_pairs(%{
         strategies: strategies,
         baseline: baseline,
         budgets: budgets,
         outcome: outcome
       }) do
    for strategy <- strategies, budget <- budgets, into: MapSet.new() do
      {strategy, budget, baseline, outcome}
    end
  end

  defp single_variant(%{} = manifest) do
    case Map.get(manifest, "model_variants") do
      [%{"id" => id}] when is_binary(id) and id != "" -> {:ok, id}
      _variants -> :error
    end
  end

  defp configuration(%{} = manifest) do
    with %{} = analysis <- Map.get(manifest, "analysis"),
         :ok <- correction(analysis),
         [_first | _rest] = comparisons <- Map.get(analysis, "primary_comparisons") do
      {:ok, %{analysis: analysis, comparisons: comparisons}}
    else
      _error -> :error
    end
  end

  defp correction(analysis) do
    if Map.get(analysis, "multiplicity_correction") == @correction, do: :ok, else: :error
  end

  defp settings(%{analysis: analysis}) do
    with {:ok, confidence} <- finite(analysis["confidence_level"]),
         true <- confidence > 0 and confidence < 1,
         {:ok, bootstrap} <- positive_integer(analysis["bootstrap_resamples"]),
         {:ok, permutation} <- positive_integer(analysis["permutation_resamples"]),
         {:ok, seed} <- non_negative_integer(analysis["seed"]) do
      {:ok,
       %{
         confidence_level: confidence,
         bootstrap_resamples: bootstrap,
         permutation_resamples: permutation,
         seed: seed
       }}
    else
      _error -> :error
    end
  end

  defp comparison_pairs(%{comparisons: comparisons}) do
    Enum.reduce_while(comparisons, {:ok, []}, &collect_pair/2)
  end

  defp collect_pair(comparison, {:ok, acc}) do
    case comparison_pair(comparison) do
      {:ok, pair} -> push_pair(pair, acc)
      :error -> {:halt, :error}
    end
  end

  defp push_pair(pair, acc) do
    if pair in acc, do: {:halt, :error}, else: {:cont, {:ok, [pair | acc]}}
  end

  defp comparison_pair(%{} = comparison) do
    with {:ok, strategy} <- non_empty_string(comparison["strategy"]),
         {:ok, baseline} <- non_empty_string(comparison["baseline"]),
         {:ok, budget} <- positive_integer(comparison["budget"]),
         {:ok, outcome} <- non_empty_string(comparison["outcome"]),
         {:ok, _variant} <- non_empty_string(comparison["model_variant"]),
         {:ok, _baseline_variant} <- non_empty_string(comparison["baseline_model_variant"]) do
      {:ok, {strategy, budget, baseline, outcome}}
    else
      _error -> :error
    end
  end

  defp comparison_pair(_comparison), do: :error

  defp string_list(values) when is_list(values) do
    if Enum.all?(values, &(is_binary(&1) and &1 != "")), do: {:ok, values}, else: :error
  end

  defp string_list(_values), do: :error

  defp integer_list(values) when is_list(values) do
    integers = Enum.map(values, &coerce_integer/1)

    if Enum.all?(integers, &is_integer/1), do: {:ok, integers}, else: :error
  end

  defp integer_list(_values), do: :error

  defp non_empty_string(value) when is_binary(value) and value != "", do: {:ok, value}
  defp non_empty_string(_value), do: :error

  defp positive_integer(value) do
    case coerce_integer(value) do
      integer when is_integer(integer) and integer > 0 -> {:ok, integer}
      _value -> :error
    end
  end

  defp non_negative_integer(value) do
    case coerce_integer(value) do
      integer when is_integer(integer) and integer >= 0 -> {:ok, integer}
      _value -> :error
    end
  end

  defp coerce_integer(value) when is_integer(value), do: value

  defp coerce_integer(value) when is_binary(value) do
    if Regex.match?(~r/\A[+-]?\d+\z/, value), do: String.to_integer(value)
  end

  defp coerce_integer(_value), do: nil

  defp finite(value) when is_number(value), do: {:ok, value * 1.0}

  defp finite(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _error -> :error
    end
  end

  defp finite(_value), do: :error
end
