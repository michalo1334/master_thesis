defmodule NetworkDefense.Evaluation.PlanPreview do
  @moduledoc """
  Describes the plans and comparisons of a validated evaluation manifest.

  Pure module. It assumes the manifest has already passed
  `NetworkDefense.Evaluation.Contracts.EvaluationManifest`. It does not
  resolve graphs, derive attack seeds, or touch persistence; it only expands
  what is declared.
  """

  alias NetworkDefense.Optimization.ModelVariant

  @type plan :: {ModelVariant.t(), String.t(), pos_integer(), non_neg_integer()}

  @type plan_group :: %{
          model_variant: String.t(),
          strategy: String.t(),
          budget: pos_integer(),
          selection_seeds: [non_neg_integer()]
        }

  @type comparison_group :: %{
          index: non_neg_integer(),
          tested: plan_group(),
          baseline: plan_group(),
          outcome: String.t()
        }

  @spec plans(map()) :: [plan()]
  def plans(manifest) do
    manifest
    |> Map.get("strategy_runs", [])
    |> Enum.flat_map(fn run ->
      Enum.map(
        Map.get(run, "selection_seeds", []),
        &{model_variant!(run["model_variant"]), run["strategy"], run["budget"], &1}
      )
    end)
    |> Enum.sort()
  end

  @spec declared?(map(), String.t(), String.t(), pos_integer()) :: boolean()
  def declared?(%{"strategy_runs" => runs}, variant, strategy, budget),
    do:
      Enum.any?(
        runs,
        &(is_map(&1) and &1["model_variant"] == variant and &1["strategy"] == strategy and
            &1["budget"] == budget)
      )

  def declared?(_, _, _, _), do: false

  @spec selection_seeds(map(), String.t(), String.t(), pos_integer()) ::
          [non_neg_integer()] | nil
  def selection_seeds(%{"strategy_runs" => runs}, variant, strategy, budget) do
    run =
      Enum.find(
        runs,
        &(is_map(&1) and &1["model_variant"] == variant and &1["strategy"] == strategy and
            &1["budget"] == budget)
      )

    if is_map(run), do: Map.get(run, "selection_seeds"), else: nil
  end

  def selection_seeds(_, _, _, _), do: nil

  @spec comparison_groups(map()) :: [comparison_group()]
  def comparison_groups(manifest) do
    manifest
    |> Map.get("analysis", %{})
    |> Map.get("primary_comparisons", [])
    |> Enum.with_index()
    |> Enum.map(fn {comparison, index} ->
      %{
        index: index,
        tested:
          group(
            manifest,
            comparison["model_variant"],
            comparison["strategy"],
            comparison["budget"]
          ),
        baseline:
          group(
            manifest,
            comparison["baseline_model_variant"],
            comparison["baseline"],
            comparison["budget"]
          ),
        outcome: comparison["outcome"]
      }
    end)
  end

  defp group(manifest, variant, strategy, budget),
    do: %{
      model_variant: variant,
      strategy: strategy,
      budget: budget,
      selection_seeds: selection_seeds(manifest, variant, strategy, budget) || []
    }

  defp model_variant!(wire) do
    {:ok, variant} = ModelVariant.from_wire(wire)
    variant
  end
end
