defmodule NetworkDefense.Evaluation.Contracts.StudySpecification do
  @moduledoc """
  Validates and describes saved study-specification JSON.

  JSON keys stay strings. The validator mirrors the analysis-service study
  loader in `evaluation/analysis/src/network_defense_analysis/study.py` so a
  saved version runs without a later loader failure. It requires the
  declaration blocks the loader reads: `study_id`, `specification_version`,
  `tiers`, `expected_family`, `pilot`, `multiplicity_correction`, and both seed
  schedules. It also enforces the cross-field rules: one `holm` correction,
  disjoint pilot and final schedules, and a baseline that is not an
  alternative.

  Declared tiers may be plain label strings or objects with a `label` field.
  `describe/1` normalizes both forms to label strings. `validate_json/1`
  rejects nested non-string keys and non-JSON values before a save or describe
  so later canonical encoding cannot fail.

  Numeric scalars follow the analysis-service functions `_integer` and
  `_finite` in `contracts.py`: `specification_version`, budgets, candidate
  counts, subsamples, seeds, `ci_half_width`, and `guard_quantile` accept the
  same integer and numeric-string forms, and `validate/1` returns the coerced
  numbers. Finite strings also accept surrounding whitespace and single
  underscores between digits, matching Python `float()`; non-finite strings
  fail. Tier labels are declarations, not scalars: they stay validated strings
  and are never coerced. The bundle builder hydrates them afterwards.
  """

  alias NetworkDefense.Evaluation.StudyTierValidator

  @max_study_id_bytes 255
  @min_plan_count 5
  @min_attack_count 10
  @max_pilot_candidates 64
  @max_pilot_subsamples 500
  @multiplicity_correction "holm"
  @outcome "mission_impact"
  @selection_rule "lowest_predicted_runtime"
  @integer_pattern ~r/\A[+-]?\d+\z/
  # Mirrors the finite numeric-string grammar Python `float()` accepts: optional
  # sign, digits with single underscores between them, an optional fractional
  # part, and an optional exponent. `inf`, `nan`, and overflowing values fail
  # the float parse below, which matches the non-finite rejection in `_finite`.
  @finite_pattern ~r/\A[+-]?(?:(?:\d(?:_?\d)*)(?:\.(?:\d(?:_?\d)*)?)?|\.(?:\d(?:_?\d)*))(?:[eE][+-]?(?:\d(?:_?\d)*))?\z/

  @type error :: %{path: String.t(), message: String.t()}

  @type description :: %{
          study_id: String.t(),
          specification_version: pos_integer(),
          tiers: [String.t()]
        }

  @spec parse(String.t()) :: {:ok, map()} | {:error, [error()]}
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, specification} -> validate(specification)
      {:error, _reason} -> error("$", "invalid JSON")
    end
  end

  @spec validate(map()) :: {:ok, map()} | {:error, [error()]}
  def validate(specification) when is_map(specification) do
    with :ok <- study_id(specification),
         {:ok, specification_version} <- specification_version(specification),
         :ok <- tiers(specification),
         :ok <- expected_family(specification),
         :ok <- pilot(specification),
         :ok <- multiplicity_correction(specification),
         :ok <- seed_schedules(specification) do
      {:ok, normalize(specification, specification_version)}
    end
  end

  def validate(_specification), do: error("$", "study specification must be a JSON object")

  @doc """
  Reports whether a value is canonical JSON.

  Maps must use string keys and every nested value must be a JSON value. The
  context enforces this before persistence because saved content is
  canonicalised later.
  """
  @spec validate_json(term()) :: :ok | {:error, [error()]}
  def validate_json(value), do: json_value(value, "$")

  @spec describe(map()) :: {:ok, description()} | {:error, [error()]}
  def describe(specification) when is_map(specification) do
    case validate(specification) do
      {:ok, validated} ->
        {:ok,
         %{
           study_id: validated["study_id"],
           specification_version: validated["specification_version"],
           tiers: declared_labels(validated["tiers"])
         }}

      {:error, _reason} = error ->
        error
    end
  end

  def describe(_specification), do: error("$", "study specification must be a JSON object")

  defp json_value(value, path) when is_map(value) do
    Enum.reduce_while(value, :ok, &json_entry(&1, &2, path))
  end

  defp json_value(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      step(json_value(item, index_path(path, index)))
    end)
  end

  defp json_value(value, _path)
       when is_binary(value) or is_integer(value) or is_float(value),
       do: :ok

  defp json_value(value, _path) when is_boolean(value) or is_nil(value), do: :ok
  defp json_value(_value, path), do: error(path, "must be a JSON value")

  defp json_entry({key, item}, :ok, path) when is_binary(key),
    do: step(json_value(item, child_path(path, key)))

  defp json_entry({_key, _item}, :ok, path), do: {:halt, error(path, "must use string keys")}

  defp step(:ok), do: {:cont, :ok}
  defp step({:error, _reason} = error), do: {:halt, error}

  defp study_id(specification) do
    case Map.get(specification, "study_id") do
      value when is_binary(value) ->
        if String.trim(value) != "" and byte_size(value) <= @max_study_id_bytes do
          :ok
        else
          error("study_id", "must be a non-empty string of at most #{@max_study_id_bytes} bytes")
        end

      _value ->
        error("study_id", "must be a non-empty string")
    end
  end

  defp specification_version(specification) do
    case to_integer(Map.get(specification, "specification_version")) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _value -> error("specification_version", "must be a positive integer")
    end
  end

  defp tiers(specification) do
    case Map.get(specification, "tiers") do
      [_first | _rest] = tiers -> validate_tiers(tiers)
      [] -> error("tiers", "must declare at least one tier")
      _value -> error("tiers", "must be a non-empty list")
    end
  end

  defp validate_tiers(tiers) do
    with {:ok, labels} <- labels(tiers) do
      if length(labels) == length(Enum.uniq(labels)) do
        :ok
      else
        error("tiers", "must contain unique tier labels")
      end
    end
  end

  defp labels(tiers) do
    tiers
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, labels} ->
      case declared_label(entry, index) do
        {:ok, label} -> {:cont, {:ok, [label | labels]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, labels} -> {:ok, Enum.reverse(labels)}
      {:error, _reason} = error -> error
    end
  end

  defp declared_label(label, _index) when is_binary(label), do: safe_label(label, "tiers")

  defp declared_label(%{"label" => label}, index) when is_binary(label),
    do: safe_label(label, "tiers.#{index}.label")

  defp declared_label(_entry, index),
    do: error("tiers.#{index}", "must be a tier label or an object with a label")

  defp safe_label("", path), do: error(path, "must be a non-empty string")

  defp safe_label(label, path) do
    if StudyTierValidator.safe_label?(label),
      do: {:ok, label},
      else: error(path, "must be a safe tier label")
  end

  defp expected_family(specification) do
    case Map.get(specification, "expected_family") do
      %{} = family -> validate_expected_family(family)
      _value -> error("expected_family", "must be an object")
    end
  end

  defp validate_expected_family(family) do
    with :ok <- family_strategies(family),
         :ok <- family_baseline(family),
         :ok <- family_budgets(family) do
      family_outcome(family)
    end
  end

  defp family_strategies(family) do
    case Map.get(family, "strategies") do
      [_first | _rest] = strategies -> unique_texts(strategies, "expected_family.strategies")
      _value -> error("expected_family.strategies", "must be a non-empty list")
    end
  end

  defp family_baseline(family) do
    baseline = Map.get(family, "baseline")
    strategies = Map.get(family, "strategies")

    cond do
      not text?(baseline) ->
        error("expected_family.baseline", "must be a non-empty string")

      is_list(strategies) and baseline in strategies ->
        error("expected_family.baseline", "must not be an alternative")

      true ->
        :ok
    end
  end

  defp family_budgets(family) do
    case Map.get(family, "budgets") do
      [_first | _rest] = budgets -> unique_budgets(budgets)
      _value -> error("expected_family.budgets", "must be a non-empty list")
    end
  end

  defp unique_budgets(budgets) do
    integers = Enum.map(budgets, &to_integer/1)

    cond do
      not Enum.all?(integers, &(is_integer(&1) and &1 > 0)) ->
        error("expected_family.budgets", "must contain unique positive integers")

      length(Enum.uniq(integers)) != length(integers) ->
        error("expected_family.budgets", "must contain unique positive integers")

      true ->
        :ok
    end
  end

  defp family_outcome(family) do
    if Map.get(family, "outcome") == @outcome do
      :ok
    else
      error("expected_family.outcome", "must be \"#{@outcome}\"")
    end
  end

  defp unique_texts(values, path) do
    cond do
      not Enum.all?(values, &text?/1) -> error(path, "must be non-empty strings")
      length(Enum.uniq(values)) != length(values) -> error(path, "must be unique")
      true -> :ok
    end
  end

  defp pilot(specification) do
    case Map.get(specification, "pilot") do
      %{} = pilot -> validate_pilot(pilot)
      _value -> error("pilot", "must be an object")
    end
  end

  defp validate_pilot(pilot) do
    with :ok <- pilot_target(pilot),
         :ok <- pilot_candidates(pilot, "plan_count_candidates", @min_plan_count),
         :ok <- pilot_candidates(pilot, "attacks_per_plan_candidates", @min_attack_count) do
      pilot_options(pilot)
    end
  end

  defp pilot_target(pilot) do
    case to_finite(Map.get(pilot, "ci_half_width")) do
      value when is_number(value) and value > 0 -> :ok
      _value -> error("pilot.ci_half_width", "must be a positive number")
    end
  end

  defp pilot_candidates(pilot, key, minimum) do
    case Map.get(pilot, key) do
      [_first | _rest] = candidates -> validate_candidates(candidates, key, minimum)
      _value -> error("pilot.#{key}", "must be a non-empty list")
    end
  end

  defp validate_candidates(candidates, key, minimum) do
    path = "pilot.#{key}"
    integers = Enum.map(candidates, &to_integer/1)

    cond do
      length(candidates) > @max_pilot_candidates ->
        error(path, "must contain at most #{@max_pilot_candidates} entries")

      not Enum.all?(integers, &(is_integer(&1) and &1 >= minimum)) ->
        error(path, "entries must be integers of at least #{minimum}")

      length(Enum.uniq(integers)) != length(integers) ->
        error(path, "entries must be unique")

      integers != Enum.sort(integers) ->
        error(path, "entries must be sorted")

      true ->
        :ok
    end
  end

  defp pilot_options(pilot) do
    with :ok <- optional(pilot, "guard_quantile", &quantile?/1, "must be between zero and one"),
         :ok <-
           optional(
             pilot,
             "subsamples",
             &subsamples?/1,
             "must be an integer between 1 and #{@max_pilot_subsamples}"
           ),
         :ok <-
           optional(pilot, "seed", &non_negative_integer?/1, "must be a non-negative integer") do
      optional(
        pilot,
        "selection_rule",
        &(&1 == @selection_rule),
        "must be \"#{@selection_rule}\""
      )
    end
  end

  defp optional(map, key, predicate, message) do
    case Map.fetch(map, key) do
      {:ok, value} -> if predicate.(value), do: :ok, else: error("pilot.#{key}", message)
      :error -> :ok
    end
  end

  defp multiplicity_correction(specification) do
    if Map.get(specification, "multiplicity_correction") == @multiplicity_correction do
      :ok
    else
      error("multiplicity_correction", "must be \"#{@multiplicity_correction}\"")
    end
  end

  defp seed_schedules(specification) do
    with {:ok, pilot_schedule} <- seed_schedule(specification, "pilot_seed_schedule"),
         {:ok, final_schedule} <- seed_schedule(specification, "final_seed_schedule") do
      disjoint_schedules(pilot_schedule, final_schedule)
    end
  end

  defp seed_schedule(specification, name) do
    case Map.get(specification, name) do
      %{} = schedule ->
        with {:ok, selection} <- seed_list(schedule, name, "selection"),
             {:ok, evaluation} <- seed_list(schedule, name, "evaluation") do
          {:ok, %{selection: MapSet.new(selection), evaluation: MapSet.new(evaluation)}}
        end

      _value ->
        error(name, "must be an object")
    end
  end

  defp seed_list(schedule, name, key) do
    case Map.get(schedule, key) do
      [_first | _rest] = seeds -> unique_seeds(seeds, "#{name}.#{key}")
      _value -> error("#{name}.#{key}", "must be a non-empty list")
    end
  end

  defp unique_seeds(seeds, path) do
    integers = Enum.map(seeds, &to_integer/1)

    if Enum.all?(integers, &(is_integer(&1) and &1 >= 0)) and
         length(Enum.uniq(integers)) == length(integers) do
      {:ok, integers}
    else
      error(path, "must contain unique non-negative integers")
    end
  end

  defp disjoint_schedules(pilot, final) do
    Enum.reduce_while([:selection, :evaluation], :ok, fn key, :ok ->
      if MapSet.disjoint?(pilot[key], final[key]) do
        {:cont, :ok}
      else
        {:halt, error("pilot_seed_schedule.#{key}", "must not overlap the final schedule")}
      end
    end)
  end

  defp declared_labels(tiers), do: Enum.map(tiers, &label/1)

  defp label(value) when is_binary(value), do: value
  defp label(%{"label" => label}), do: label

  # Mirrors `contracts._integer`: an integer scalar is an integer or a digit
  # string with an optional sign. Booleans and floats are never integers.
  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    if Regex.match?(@integer_pattern, value), do: String.to_integer(value)
  end

  defp to_integer(_value), do: nil

  # Mirrors `contracts._finite`: a finite number is a number or a numeric
  # string, always returned as a float. Like Python `float()`, a string may be
  # surrounded by whitespace and may use single underscores between digits.
  # Booleans and non-finite strings fail.
  defp to_finite(value) when is_number(value), do: value * 1.0

  defp to_finite(value) when is_binary(value), do: value |> String.trim() |> parse_finite()

  defp to_finite(_value), do: nil

  defp parse_finite(value) do
    if Regex.match?(@finite_pattern, value) do
      value |> String.replace("_", "") |> normalize_decimal() |> Float.parse() |> full_float()
    end
  end

  defp full_float({number, ""}), do: number
  defp full_float(_other), do: nil

  defp normalize_decimal(value) do
    value
    |> String.replace(~r/\A([+-]?)\./, "\\g{1}0.")
    |> String.replace(~r/\.(?=[eE]|\z)/, ".0")
  end

  defp normalize(specification, specification_version) do
    specification
    |> Map.put("specification_version", specification_version)
    |> Map.update("expected_family", %{}, &normalize_family/1)
    |> Map.update("pilot", %{}, &normalize_pilot/1)
    |> Map.update("pilot_seed_schedule", %{}, &normalize_schedule/1)
    |> Map.update("final_seed_schedule", %{}, &normalize_schedule/1)
  end

  defp normalize_family(family), do: Map.update(family, "budgets", [], &coerce_integers/1)

  defp normalize_pilot(pilot) do
    pilot
    |> Map.update("ci_half_width", nil, &to_finite/1)
    |> coerce_candidates("plan_count_candidates")
    |> coerce_candidates("attacks_per_plan_candidates")
    |> coerce_optional("guard_quantile", &to_finite/1)
    |> coerce_optional("subsamples", &to_integer/1)
    |> coerce_optional("seed", &to_integer/1)
  end

  defp coerce_candidates(pilot, key), do: Map.update(pilot, key, [], &coerce_integers/1)

  defp coerce_optional(map, key, coerce) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, coerce.(value))
      :error -> map
    end
  end

  defp normalize_schedule(schedule) do
    schedule
    |> Map.update("selection", [], &coerce_integers/1)
    |> Map.update("evaluation", [], &coerce_integers/1)
  end

  defp coerce_integers(values), do: Enum.map(values, &to_integer/1)

  defp text?(value), do: is_binary(value) and value != ""
  defp child_path("$", key), do: key
  defp child_path(path, key), do: "#{path}.#{key}"
  defp index_path("$", index), do: "[#{index}]"
  defp index_path(path, index), do: "#{path}[#{index}]"

  defp subsamples?(value) do
    case to_integer(value) do
      subsamples when is_integer(subsamples) -> subsamples in 1..@max_pilot_subsamples
      _value -> false
    end
  end

  defp quantile?(value) do
    case to_finite(value) do
      quantile when is_number(quantile) -> quantile > 0 and quantile < 1
      _value -> false
    end
  end

  defp non_negative_integer?(value) do
    case to_integer(value) do
      integer when is_integer(integer) -> integer >= 0
      _value -> false
    end
  end

  defp error(path, message), do: {:error, [%{path: path, message: message}]}
end
