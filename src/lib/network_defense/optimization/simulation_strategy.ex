defmodule NetworkDefense.Optimization.SimulationStrategy do
  @moduledoc false

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Simulation.Seed
  alias NetworkDefense.Simulations

  @doc """
  Builds a simulation-backed strategy struct for `module` from validated params.
  """
  @spec new(module(), Graph.t(), map()) :: {:ok, struct()} | {:error, Simulations.Errors.error()}
  def new(module, graph, %{simulation_params: simulation_params}) do
    with :ok <-
           Simulations.validate_initial_foothold(
             graph,
             simulation_params.initial_foothold_node_id
           ) do
      {:ok,
       struct!(module,
         initial_attacker_state:
           Simulations.initial_attacker_state(graph, simulation_params.initial_foothold_node_id),
         rules: Simulations.default_rules(),
         run_count: simulation_params.monte_carlo_trials,
         iteration_count: simulation_params.iterations_per_run,
         seed: simulation_seed(simulation_params),
         max_attempts: simulation_params.max_attempts
       )}
    end
  end

  defp simulation_seed(%{generate_seed: true}), do: Seed.random()
  defp simulation_seed(%{seed: seed}), do: seed

  @doc """
  Enumerates every eligible `{action, target}` candidate across the graph.
  """
  @spec candidate_actions([module()], Graph.t()) :: [DefenseAction.t()]
  def candidate_actions(action_types, graph) do
    Enum.flat_map(action_types, fn action_type ->
      action = struct!(action_type)
      eligible_types = DefenseAction.eligible_types(action)

      (Graph.nodes(graph) ++ Graph.edges(graph))
      |> Enum.filter(&(&1.type in eligible_types))
      |> Enum.map(&DefenseAction.with_target_id(action, &1.id))
    end)
  end
end
