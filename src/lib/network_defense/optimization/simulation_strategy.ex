defmodule NetworkDefense.Optimization.SimulationStrategy do
  @moduledoc false

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.DefenseActions.RevokeCredential
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Relationships.AuthenticatesTo
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
  Enumerates every eligible `{action, target}` candidate that still changes the graph.

  Candidates come from the current nodes and edges, so a patch or a block always
  targets an edge that exists. A credential revocation is useful only while the
  credential holds an outgoing `AuthenticatesTo` edge.
  """
  @spec candidate_actions([module()], Graph.t()) :: [DefenseAction.t()]
  def candidate_actions(action_types, graph) do
    authenticating_node_ids =
      graph
      |> Graph.edges()
      |> Enum.filter(&(&1.type == AuthenticatesTo))
      |> MapSet.new(& &1.from_id)

    Enum.flat_map(Enum.uniq(action_types), fn action_type ->
      action = struct!(action_type)
      eligible_types = DefenseAction.eligible_types(action)

      (Graph.nodes(graph) ++ Graph.edges(graph))
      |> Enum.filter(
        &(&1.type in eligible_types and effective_target?(action, &1, authenticating_node_ids))
      )
      |> Enum.map(&DefenseAction.with_target_id(action, &1.id))
    end)
  end

  defp effective_target?(%RevokeCredential{}, %Node{id: node_id}, authenticating_node_ids) do
    MapSet.member?(authenticating_node_ids, node_id)
  end

  defp effective_target?(_action, _target, _authenticating_node_ids), do: true
end
