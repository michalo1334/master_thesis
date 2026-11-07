defmodule NetworkDefense.Evaluation2.Study.AuthoredDefinition do
  @moduledoc "Declared settings of a frozen revision, with an exact decimal seed."
  use Spectral

  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Definition.Candidate

  @type alternative :: %{
          strategy: String.t(),
          objective: String.t() | nil,
          monte_carlo_trials: pos_integer() | nil
        }
  @type tier :: %{
          tier: String.t(),
          graph_revision_id: String.t(),
          foothold_node_id: String.t(),
          budgets: [pos_integer()],
          alternatives: [alternative()]
        }
  @type t :: %__MODULE__{
          study_id: String.t(),
          revision: pos_integer(),
          seed: String.t(),
          family_id: String.t(),
          family_alpha: float(),
          confidence_level: float(),
          feasibility: Definition.Defense.feasibility(),
          allowed_action_types: [String.t()],
          iterations_per_run: pos_integer(),
          max_attempts: pos_integer(),
          rules: [String.t()],
          tiers: [tier()],
          candidates: [Candidate.t()],
          extra_pool_plans: non_neg_integer(),
          extra_pool_attacks: non_neg_integer(),
          outer_subsamples: pos_integer(),
          target_half_width: float(),
          guard_quantile: float()
        }

  defstruct [
    :study_id,
    :revision,
    :seed,
    :family_id,
    :family_alpha,
    :confidence_level,
    :feasibility,
    :allowed_action_types,
    :iterations_per_run,
    :max_attempts,
    :rules,
    :tiers,
    :candidates,
    :extra_pool_plans,
    :extra_pool_attacks,
    :outer_subsamples,
    :target_half_width,
    :guard_quantile
  ]

  @doc "Build the authored view from a validated definition."
  @spec new(Definition.t()) :: t()
  def new(%Definition{} = definition) do
    %__MODULE__{
      study_id: definition.study.id,
      revision: definition.study.revision,
      seed: Integer.to_string(definition.seed),
      family_id: definition.family.id,
      family_alpha: definition.family.alpha,
      confidence_level: definition.analysis.confidence_level,
      feasibility: definition.defense.feasibility,
      allowed_action_types: Enum.map(definition.defense.allowed_action_types, &Atom.to_string/1),
      iterations_per_run: definition.simulation.iterations_per_run,
      max_attempts: definition.simulation.max_attempts,
      rules: Enum.map(definition.simulation.rules, &Atom.to_string/1),
      tiers: Enum.map(definition.tiers, &tier/1),
      candidates: definition.pilot.candidates,
      extra_pool_plans: definition.pilot.extra_pool.plans,
      extra_pool_attacks: definition.pilot.extra_pool.attacks,
      outer_subsamples: definition.pilot.precision.outer_subsamples,
      target_half_width: definition.pilot.precision.target_half_width,
      guard_quantile: definition.pilot.precision.guard_quantile
    }
  end

  defp tier(tier) do
    %{
      tier: tier.tier,
      graph_revision_id: tier.graph_revision_id,
      foothold_node_id: tier.initial_foothold_node_id,
      budgets: tier.budgets,
      alternatives: Enum.map(tier.alternatives, &alternative/1)
    }
  end

  defp alternative(strategy) do
    %{
      strategy: Atom.to_string(strategy.key),
      objective: strategy.scoring && Atom.to_string(strategy.scoring.objective),
      monte_carlo_trials: strategy.scoring && strategy.scoring.monte_carlo_trials
    }
  end
end
