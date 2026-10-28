defmodule NetworkDefense.Evaluation.SnapshotValidation do
  @moduledoc false

  import NetworkDefense.Evaluation.ContractSupport

  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  @max_issues 50

  def issues(comparisons, comparison_issues) do
    comparisons
    |> Enum.with_index()
    |> Enum.flat_map(fn {comparison, index} -> comparison_issues.(comparison, index) end)
    |> Kernel.++(duplicate_comparison_issues(comparisons))
    |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
    |> Enum.take(@max_issues)
  end

  def comparison_issues(position, identity, evidence, index) do
    position_issues(position, index) ++ evidence_issues(identity, evidence, index)
  end

  defp position_issues(position, index) do
    if position == index do
      []
    else
      [
        issue(
          "non_consecutive_position",
          ["comparisons", index, "position"],
          "Comparison positions must be consecutive from zero.",
          %{"declared" => position, "expected" => index}
        )
      ]
    end
  end

  defp evidence_issues(identity, evidence, index) do
    attack_count = length(evidence.attack_seeds)

    agreement_issues(identity, evidence, index) ++
      alternative_strategy_issues(identity, index) ++
      side_issues(
        evidence.alternative,
        ["comparisons", index, "evidence", "alternative"],
        attack_count
      ) ++
      side_issues(
        evidence.reference,
        ["comparisons", index, "evidence", "reference"],
        attack_count
      )
  end

  defp agreement_issues(identity, evidence, index) do
    [
      {"alternative", identity.alternative, evidence.alternative.strategy},
      {"reference", identity.reference, evidence.reference.strategy},
      {"outcome", identity.outcome, evidence.outcome}
    ]
    |> Enum.reject(fn {_field, declared, actual} -> declared == actual end)
    |> Enum.map(fn {field, declared, actual} ->
      issue(
        "identity_mismatch",
        ["comparisons", index, "identity", field],
        "The identity field must agree with the comparison evidence.",
        %{"declared" => declared, "request" => actual}
      )
    end)
  end

  defp alternative_strategy_issues(%Identity{alternative: "cvss"}, index) do
    [
      issue(
        "unsupported_alternative_strategy",
        ["comparisons", index, "identity", "alternative"],
        "The alternative strategy must not be the reference strategy.",
        %{"alternative" => "cvss"}
      )
    ]
  end

  defp alternative_strategy_issues(_identity, _index), do: []

  defp side_issues(side, path, attack_count) do
    duplicate_plan_issues(side.plans, path) ++ column_issues(side.plans, attack_count, path)
  end

  defp duplicate_plan_issues(plans, path) do
    {_seen, issues} =
      plans
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {plan, index}, {seen, issues} ->
        if MapSet.member?(seen, plan.id) do
          {seen,
           [
             issue(
               "duplicate_plan_id",
               path ++ ["plans", index, "id"],
               "Plan IDs must be unique inside one side.",
               %{"plan_id" => plan.id}
             )
             | issues
           ]}
        else
          {MapSet.put(seen, plan.id), issues}
        end
      end)

    Enum.reverse(issues)
  end

  defp column_issues(plans, attack_count, path) do
    plans
    |> Enum.with_index()
    |> Enum.reject(fn {plan, _index} -> length(plan.mission_impacts) == attack_count end)
    |> Enum.map(fn {plan, index} ->
      issue(
        "attack_column_count_mismatch",
        path ++ ["plans", index, "mission_impacts"],
        "Every plan must repeat the attack seed count.",
        %{"expected" => attack_count, "actual" => length(plan.mission_impacts)}
      )
    end)
  end

  defp duplicate_comparison_issues(comparisons) do
    {_seen, issues} =
      comparisons
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {comparison, index}, {seen, issues} ->
        key = Identity.key(comparison.identity)

        if MapSet.member?(seen, key) do
          {seen,
           [
             issue(
               "duplicate_comparison",
               ["comparisons", index, "identity"],
               "Comparison identities must be unique.",
               identity_details(key)
             )
             | issues
           ]}
        else
          {MapSet.put(seen, key), issues}
        end
      end)

    Enum.reverse(issues)
  end

  defp identity_details({tier, budget, alternative, reference, outcome}) do
    %{
      "tier" => tier,
      "budget" => budget,
      "alternative" => alternative,
      "reference" => reference,
      "outcome" => outcome
    }
  end
end
