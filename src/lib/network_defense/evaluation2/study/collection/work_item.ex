defmodule NetworkDefense.Evaluation2.Study.Collection.WorkItem do
  @moduledoc false
  use Spectral

  alias NetworkDefense.DefenseActions.Registry
  alias NetworkDefense.Evaluation2.Study.Definition.{Simulation, Strategy}
  alias NetworkDefense.Evaluation2.Study.Seed

  # Group position is definition-global. Plan position identifies the scientific
  # row inside that group. SQL item positions are phase-run-local coordinates.
  @type t :: %__MODULE__{
          group_position: non_neg_integer(),
          plan_position: non_neg_integer(),
          graph_revision: Ecto.UUID.t(),
          initial_foothold_node_id: Ecto.UUID.t(),
          strategy: Strategy.t(),
          budget: pos_integer(),
          candidate_action_types: [Registry.action_type()],
          require_pre_attack_feasibility: boolean(),
          simulation: Simulation.t(),
          mission_impact_bound: %{minimum: float(), maximum: float()},
          selection_seed: Seed.t(),
          evaluation_root: Seed.t(),
          attack_count: pos_integer()
        }
  defstruct [
    :group_position,
    :plan_position,
    :graph_revision,
    :initial_foothold_node_id,
    :strategy,
    :budget,
    :candidate_action_types,
    :require_pre_attack_feasibility,
    :simulation,
    :mission_impact_bound,
    :selection_seed,
    :evaluation_root,
    :attack_count
  ]

  def optimization_request(work, correlation_id) do
    alias NetworkDefense.Optimization.Contracts.{
      OptimizationParams,
      RunOptimizationRequest,
      SimulationSettings
    }

    scoring = work.strategy.scoring
    simulation = work.simulation

    scoring_settings =
      if scoring do
        %SimulationSettings{
          objective: scoring.objective,
          monte_carlo_trials: scoring.monte_carlo_trials,
          iterations_per_run: simulation.iterations_per_run,
          max_attempts: simulation.max_attempts,
          rules: simulation.rules
        }
      end

    foothold =
      if OptimizationParams.requires_initial_foothold?(work.strategy.key),
        do: work.initial_foothold_node_id

    %RunOptimizationRequest{
      graph_revision_id: work.graph_revision,
      correlation_id: correlation_id,
      optimization_params: %OptimizationParams{
        strategy: work.strategy.key,
        budget: work.budget,
        seed: work.selection_seed,
        candidate_action_types: work.candidate_action_types,
        require_pre_attack_feasibility: work.require_pre_attack_feasibility,
        initial_foothold_node_id: foothold,
        simulation_params: scoring_settings
      }
    }
  end

  def simulation_request(work, output_revision, correlation_id) do
    alias NetworkDefense.Simulation.Contracts.{RunSimulationRequest, SimulationParams}

    %RunSimulationRequest{
      graph_revision_id: output_revision,
      correlation_id: correlation_id,
      simulation_params: %SimulationParams{
        monte_carlo_trials: work.attack_count,
        iterations_per_run: work.simulation.iterations_per_run,
        initial_foothold_node_id: work.initial_foothold_node_id,
        seed: work.evaluation_root,
        generate_seed: false,
        max_attempts: work.simulation.max_attempts,
        rules: work.simulation.rules,
        require_pre_attack_feasibility: work.require_pre_attack_feasibility
      }
    }
  end
end
