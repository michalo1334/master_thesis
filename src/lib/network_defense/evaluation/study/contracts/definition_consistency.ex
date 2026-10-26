defmodule NetworkDefense.Evaluation.Study.Contracts.DefinitionConsistency do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  # Cross-field rules for one complete study definition.
  #
  # The shape gate proves that every field is present, strictly typed, and
  # declared. This module proves that the declared settings agree with each
  # other:
  #
  # - one tier, one strategy per tier, one candidate identifier, and one
  #   comparison identity, so no measured result is ambiguous;
  # - every comparison names a declared graph, a declared alternative, and the
  #   cvss reference, and its budget matches both declarations;
  # - every declared graph tier appears in a comparison, so no graph is
  #   collected without a question;
  # - the Final alpha equals the family alpha, so one family keeps one level;
  # - each phase declares exactly one evaluation root per tier, and the two root
  #   sets stay disjoint, so Final never replays a Pilot observation;
  # - each selection pool is unique, the two pools stay disjoint, and each pool
  #   covers the plan rows that its phase can run;
  # - the Pilot collection covers every declared candidate, because any
  #   candidate may become the resumed Final candidate.
  #
  # A seed value is not unique across the whole document. Only the rules that an
  # existing contract states are enforced, so equal values remain possible where
  # no requirement forbids them.
  #
  # Issues are bounded. Each one names a code and a path. No issue repeats a
  # submitted value, and no issue carries a document fragment.

  @max_issues 50
  @reference_strategy :cvss

  @spec validate(Definition.t()) :: :ok | {:error, StudyError.t()}
  def validate(%Definition{} = definition) do
    issues =
      (graph_issues(definition) ++
         comparison_issues(definition) ++
         candidate_issues(definition) ++
         comparison_reference_issues(definition) ++
         tier_coverage_issues(definition) ++
         alpha_issues(definition) ++
         root_role_issues(definition) ++
         root_overlap_issues(definition) ++
         selection_pool_issues(definition) ++
         capacity_issues(definition) ++
         comparison_seed_issues(definition))
      |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
      |> Enum.take(@max_issues)

    case issues do
      [] -> :ok
      _issues -> {:error, StudyError.validation_failed(issues)}
    end
  end

  defp graph_issues(definition) do
    duplicate_issues(definition.graphs, ["graphs"], "duplicate_tier", & &1.tier, "tier") ++
      duplicate_strategy_issues(definition)
  end

  defp duplicate_strategy_issues(definition) do
    for {graph, graph_index} <- Enum.with_index(definition.graphs),
        issue <-
          duplicate_issues(
            graph.strategies,
            ["graphs", graph_index, "strategies"],
            "duplicate_strategy",
            & &1.key,
            "key"
          ),
        do: issue
  end

  defp comparison_issues(definition) do
    duplicate_issues(
      definition.family.comparisons,
      ["family", "comparisons"],
      "duplicate_comparison",
      &Definition.Comparison.key/1
    )
  end

  defp candidate_issues(definition) do
    duplicate_issues(
      definition.pilot.candidates,
      ["pilot", "candidates"],
      "duplicate_candidate_id",
      & &1.id
    ) ++
      duplicate_issues(
        definition.pilot.candidates,
        ["pilot", "candidates"],
        "duplicate_candidate_counts",
        &{&1.plan_count_per_side, &1.attacks_per_plan}
      )
  end

  defp duplicate_issues(entries, path_prefix, code, identity_of, field \\ nil) do
    {_seen, issues} =
      entries
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {entry, index}, {seen, issues} ->
        identity = identity_of.(entry)

        if MapSet.member?(seen, identity) do
          details = %{"first_index" => first_index(entries, identity_of, identity)}

          {seen,
           [issue(code, entry_path(path_prefix, index, field), message(code), details) | issues]}
        else
          {MapSet.put(seen, identity), issues}
        end
      end)

    Enum.reverse(issues)
  end

  defp entry_path(path_prefix, index, nil), do: path_prefix ++ [index]
  defp entry_path(path_prefix, index, field), do: path_prefix ++ [index, field]

  # The index of the first entry with this identity. The list is small, so one
  # extra scan keeps the reducer simple.
  defp first_index(entries, identity_of, identity) do
    entries
    |> Enum.find_index(&(identity_of.(&1) == identity))
    |> Kernel.||(0)
  end

  defp comparison_reference_issues(definition) do
    definition.family.comparisons
    |> Enum.with_index()
    |> Enum.flat_map(fn {comparison, index} ->
      base = ["family", "comparisons", index]

      case find_graph(definition, comparison.tier) do
        nil ->
          [issue("unknown_reference", base ++ ["tier"], message("unknown_reference"))]

        graph ->
          tier_reference_issues(graph, comparison, base)
      end
    end)
  end

  defp tier_reference_issues(graph, comparison, base) do
    alternative = find_strategy(graph, comparison.alternative)
    reference = find_strategy(graph, comparison.reference)

    alternative_issues =
      if alternative do
        []
      else
        [issue("unknown_reference", base ++ ["alternative"], message("unknown_reference"))]
      end

    reference_issues =
      cond do
        comparison.reference != @reference_strategy ->
          [
            issue(
              "unsupported_reference",
              base ++ ["reference"],
              message("unsupported_reference")
            )
          ]

        is_nil(reference) ->
          [issue("unknown_reference", base ++ ["reference"], message("unknown_reference"))]

        true ->
          []
      end

    budget_issues =
      [alternative, reference]
      |> Enum.reject(&(is_nil(&1) or &1.budget == comparison.budget))
      |> case do
        [] -> []
        _mismatched -> [issue("budget_mismatch", base ++ ["budget"], message("budget_mismatch"))]
      end

    alternative_issues ++ reference_issues ++ budget_issues
  end

  defp tier_coverage_issues(definition) do
    compared = MapSet.new(definition.family.comparisons, & &1.tier)

    definition.graphs
    |> Enum.with_index()
    |> Enum.reject(fn {graph, _index} -> MapSet.member?(compared, graph.tier) end)
    |> Enum.map(fn {_graph, index} ->
      issue("uncovered_tier", ["graphs", index, "tier"], message("uncovered_tier"))
    end)
  end

  defp alpha_issues(definition) do
    if definition.final.analysis.alpha == definition.family.alpha do
      []
    else
      [issue("alpha_mismatch", ["final", "analysis", "alpha"], message("alpha_mismatch"))]
    end
  end

  defp root_role_issues(definition) do
    tiers = MapSet.new(definition.graphs, & &1.tier)

    Enum.flat_map(root_scopes(definition), fn {path, roots} ->
      {covered, issues} = classify_roots(roots, path, tiers)

      issues ++
        if MapSet.equal?(covered, tiers) do
          []
        else
          [issue("missing_root_role", path ++ ["roots"], message("missing_root_role"))]
        end
    end)
  end

  defp root_scopes(definition) do
    [
      {["pilot", "collection"], definition.pilot.collection.roots},
      {["final", "collection"], definition.final.collection.roots}
    ]
  end

  defp classify_roots(roots, path, tiers) do
    {covered, issues} =
      roots
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {root, index}, acc ->
        classify_root(root, path ++ ["roots", index, "tier"], tiers, acc)
      end)

    {covered, Enum.reverse(issues)}
  end

  defp classify_root(root, entry_path, tiers, {covered, issues}) do
    cond do
      not MapSet.member?(tiers, root.tier) ->
        {covered, [issue("unknown_reference", entry_path, message("unknown_reference")) | issues]}

      MapSet.member?(covered, root.tier) ->
        {covered,
         [issue("duplicate_root_role", entry_path, message("duplicate_root_role")) | issues]}

      true ->
        {MapSet.put(covered, root.tier), issues}
    end
  end

  defp root_overlap_issues(definition) do
    pilot_values = MapSet.new(definition.pilot.collection.roots, & &1.value)
    final_path = ["final", "collection", "roots"]

    definition.final.collection.roots
    |> Enum.with_index()
    |> Enum.filter(fn {root, _index} -> MapSet.member?(pilot_values, root.value) end)
    |> Enum.map(fn {_root, index} ->
      issue("overlapping_root", final_path ++ [index, "value"], message("overlapping_root"))
    end)
  end

  defp selection_pool_issues(definition) do
    pilot_path = ["pilot", "collection", "selection_seeds"]
    final_path = ["final", "collection", "selection_seeds"]
    pilot_seeds = definition.pilot.collection.selection_seeds
    final_seeds = definition.final.collection.selection_seeds

    duplicate_values(pilot_seeds, pilot_path, "duplicate_selection_seed") ++
      duplicate_values(final_seeds, final_path, "duplicate_selection_seed") ++
      overlapping_values(final_seeds, MapSet.new(pilot_seeds), final_path)
  end

  defp duplicate_values(values, path, code) do
    {_seen, issues} =
      values
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {value, index}, {seen, issues} ->
        if MapSet.member?(seen, value) do
          {seen, [issue(code, path ++ [index], message(code)) | issues]}
        else
          {MapSet.put(seen, value), issues}
        end
      end)

    Enum.reverse(issues)
  end

  defp overlapping_values(values, other, path) do
    values
    |> Enum.with_index()
    |> Enum.filter(fn {value, _index} -> MapSet.member?(other, value) end)
    |> Enum.map(fn {_value, index} ->
      issue("overlapping_selection_seed", path ++ [index], message("overlapping_selection_seed"))
    end)
  end

  defp capacity_issues(definition) do
    candidates = definition.pilot.candidates
    largest_plans = candidates |> Enum.map(& &1.plan_count_per_side) |> Enum.max()
    largest_attacks = candidates |> Enum.map(& &1.attacks_per_plan) |> Enum.max()

    plan_issues =
      capacity_issue(
        definition.pilot.collection.plan_count_per_side,
        largest_plans,
        ["pilot", "collection", "plan_count_per_side"],
        "insufficient_pilot_plans"
      )

    attack_issues =
      capacity_issue(
        definition.pilot.collection.attacks_per_plan,
        largest_attacks,
        ["pilot", "collection", "attacks_per_plan"],
        "insufficient_pilot_attacks"
      )

    pool_issues =
      capacity_issue(
        Enum.count(definition.pilot.collection.selection_seeds),
        definition.pilot.collection.plan_count_per_side,
        ["pilot", "collection", "selection_seeds"],
        "insufficient_selection_seeds"
      ) ++
        capacity_issue(
          Enum.count(definition.final.collection.selection_seeds),
          largest_plans,
          ["final", "collection", "selection_seeds"],
          "insufficient_selection_seeds"
        )

    plan_issues ++ attack_issues ++ pool_issues
  end

  defp capacity_issue(actual, required, path, code) do
    if actual < required do
      [issue(code, path, message(code), %{"required" => required, "actual" => actual})]
    else
      []
    end
  end

  defp comparison_seed_issues(definition) do
    required = Enum.count(definition.family.comparisons)
    actual = Enum.count(definition.final.analysis.comparison_seeds)

    if actual == required do
      []
    else
      [
        issue(
          "comparison_seed_count",
          ["final", "analysis", "comparison_seeds"],
          message("comparison_seed_count"),
          %{"required" => required, "actual" => actual}
        )
      ]
    end
  end

  defp find_graph(definition, tier), do: Enum.find(definition.graphs, &(&1.tier == tier))

  # A comparison and a typed strategy both hold the closed strategy identifier
  # as an atom.
  defp find_strategy(graph, key), do: Enum.find(graph.strategies, &(&1.key == key))

  defp issue(code, path, message, details \\ %{}) do
    %{"code" => code, "path" => path, "message" => message, "details" => details}
  end

  defp message("duplicate_tier"), do: "Two graphs must not declare the same tier."
  defp message("duplicate_strategy"), do: "One tier must not declare the same strategy twice."

  defp message("duplicate_comparison"),
    do: "Two comparisons must not declare the same identity."

  defp message("duplicate_candidate_id"),
    do: "Two candidates must not declare the same identifier."

  defp message("duplicate_candidate_counts"),
    do: "Two candidates must not declare the same counts."

  defp message("unknown_reference"),
    do: "The value must name a declaration of this study definition."

  defp message("unsupported_reference"),
    do: "The reference side must be the cvss strategy."

  defp message("budget_mismatch"),
    do: "The comparison budget must equal the declared strategy budget."

  defp message("uncovered_tier"),
    do: "Every declared graph tier must appear in a comparison."

  defp message("alpha_mismatch"),
    do: "The final alpha must equal the declared family alpha."

  defp message("missing_root_role"),
    do: "Each phase must declare one evaluation root for every declared tier."

  defp message("duplicate_root_role"),
    do: "One phase must not declare two roots for one tier."

  defp message("overlapping_root"),
    do: "A Final root must not repeat a Pilot root value."

  defp message("duplicate_selection_seed"),
    do: "One selection pool must not repeat a seed value."

  defp message("overlapping_selection_seed"),
    do: "The Final selection pool must not repeat a Pilot seed value."

  defp message("insufficient_pilot_plans"),
    do: "The Pilot plan count must cover every declared candidate."

  defp message("insufficient_pilot_attacks"),
    do: "The Pilot attack count must cover every declared candidate."

  defp message("insufficient_selection_seeds"),
    do: "The selection pool must cover every plan row of its phase."

  defp message("comparison_seed_count"),
    do: "The Final comparison seeds must hold one seed per declared comparison."

  defp path_sort_key(path) do
    Enum.map(path, fn
      segment when is_integer(segment) -> {0, segment, ""}
      segment when is_binary(segment) -> {1, 0, segment}
    end)
  end
end
