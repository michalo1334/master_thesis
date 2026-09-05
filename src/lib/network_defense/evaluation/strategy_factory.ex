defmodule NetworkDefense.Evaluation.StrategyFactory do
  @moduledoc """
  Constructs optimization strategy values and resolves model settings for an
  evaluation plan.

  Pure module. It does not query, write, start jobs, or open transactions. It
  converts a resolved evaluation plan and its seed schedule into the strategy
  value the optimizer consumes.
  """

  alias NetworkDefense.Evaluation.SeedSchedule
  alias NetworkDefense.Graph.Graph

  alias NetworkDefense.Optimization.{
    CvssStrategy,
    ModelVariant,
    NullStrategy,
    RandomStrategy,
    SimulatedAnnealingStrategy,
    SimulationInformedStrategy,
    SimulationStrategy,
    TopologySegmentationStrategy
  }

  @spec build(String.t(), Graph.t(), SeedSchedule.t(), non_neg_integer(), map()) ::
          {:ok, struct()} | {:error, term()}
  def build(strategy, graph, schedule, selection_seed, model) do
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

  @spec simulation_config(struct()) :: map() | nil
  def simulation_config(%{seed: seed}) when is_integer(seed), do: %{seed: seed}
  def simulation_config(_strategy), do: nil

  @spec model_settings(map(), ModelVariant.t()) :: {:ok, map()} | {:error, String.t()}
  def model_settings(manifest, model_variant) do
    if model_variant in manifest_variants(manifest) do
      {:ok, ModelVariant.definition(model_variant)}
    else
      {:error, "unknown model variant #{ModelVariant.to_wire(model_variant)}"}
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

  defp manifest_variants(manifest) do
    manifest
    |> Map.get("model_variants", [])
    |> Enum.map(&model_variant!(&1["id"]))
  end

  defp model_variant!(wire) do
    {:ok, variant} = ModelVariant.from_wire(wire)
    variant
  end
end
