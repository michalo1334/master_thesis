defmodule NetworkDefense.Optimization.SimulationStrategy do
  @moduledoc false

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Rules.Registry, as: RulesRegistry
  alias NetworkDefense.Simulation.Simulator

  @doc """
  Builds a simulation-backed strategy struct for `module` from validated params.

  Scoring reads the top-level foothold of the optimization request and the
  explicit scoring settings: the objective, the rule subset, and the counts.
  No runtime default fills an absent scientific value.
  """
  @spec new(module(), Graph.t(), map()) :: {:ok, struct()} | {:error, atom()}
  def new(module, graph, params) do
    scoring = params.simulation_params

    with :ok <- Simulator.validate_initial_foothold(graph, params.initial_foothold_node_id),
         {:ok, rules} <- resolve_rules(scoring.rules) do
      {:ok,
       struct!(module,
         initial_attacker_state:
           Simulator.initial_attacker_state(graph, params.initial_foothold_node_id),
         rules: rules,
         run_count: scoring.monte_carlo_trials,
         iteration_count: scoring.iterations_per_run,
         seed: params.seed,
         max_attempts: scoring.max_attempts,
         objective: scoring.objective,
         require_pre_attack_feasibility: params.require_pre_attack_feasibility
       )}
    end
  end

  defp resolve_rules(values) do
    case RulesRegistry.resolve(values) do
      {:ok, rules} -> {:ok, rules}
      {:error, :unknown_rule} -> {:error, :invalid_request}
    end
  end

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
