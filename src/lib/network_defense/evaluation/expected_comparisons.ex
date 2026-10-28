defmodule NetworkDefense.Evaluation.ExpectedComparisons do
  @moduledoc false

  import NetworkDefense.Evaluation.ContractSupport

  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  def duplicate_issues(identities) do
    {_seen, issues} =
      identities
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {identity, index}, {seen, issues} ->
        key = Identity.key(identity)

        if MapSet.member?(seen, key) do
          {seen,
           [
             issue(
               "duplicate_expected_identity",
               ["expected_comparisons", index],
               "Expected comparison identities must be unique.",
               %{"tier" => identity.tier, "budget" => identity.budget}
             )
             | issues
           ]}
        else
          {MapSet.put(seen, key), issues}
        end
      end)

    Enum.reverse(issues)
  end

  def snapshot_issues(declared, stored, missing_message) do
    declared_keys = Enum.map(declared, &Identity.key/1)
    stored_keys = Enum.map(stored, &Identity.key/1)
    declared_set = MapSet.new(declared_keys)
    stored_set = MapSet.new(stored_keys)

    ordered_issues =
      if declared_keys == stored_keys do
        []
      else
        missing_issues(declared, stored_set, missing_message) ++
          unexpected_issues(stored, declared_set)
      end

    reorder_issues =
      if declared_keys != stored_keys and declared_set == stored_set do
        [
          issue(
            "changed_snapshot",
            ["expected_comparisons"],
            "The stored comparison order differs from the declared order.",
            %{}
          )
        ]
      else
        []
      end

    ordered_issues ++ reorder_issues
  end

  defp missing_issues(declared, stored_set, message) do
    declared
    |> Enum.with_index()
    |> Enum.reject(fn {identity, _index} ->
      MapSet.member?(stored_set, Identity.key(identity))
    end)
    |> Enum.map(fn {identity, index} ->
      issue(
        "missing_comparison",
        ["expected_comparisons", index],
        message,
        %{"tier" => identity.tier, "budget" => identity.budget}
      )
    end)
  end

  defp unexpected_issues(stored, declared_set) do
    stored
    |> Enum.with_index()
    |> Enum.reject(fn {identity, _index} ->
      MapSet.member?(declared_set, Identity.key(identity))
    end)
    |> Enum.map(fn {identity, index} ->
      issue(
        "unexpected_comparison",
        ["snapshot", "payload", "comparisons", index, "identity"],
        "Every stored comparison must be declared.",
        %{"tier" => identity.tier, "budget" => identity.budget}
      )
    end)
  end
end
