defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.Strategy do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.Scoring

  # One plan-selection strategy for one tier.
  #
  # The key and the budget are the identity of the declaration, so one tier
  # cannot declare the same strategy twice. The candidate action types are the
  # exact set the optimizer may choose from.
  #
  # Every strategy declares one feasibility policy, because the optimizer gate
  # runs for every plan and rejects an infeasible defense before it applies. A
  # simulation-backed strategy reuses that same flag for its scoring rejection,
  # so no second switch exists. A non-scoring strategy runs no scoring
  # simulation, so it declares no scoring block and the shape gate rejects one.
  # Random selection draws its plan choices from its own generator and states no
  # scoring objective, so it is non-scoring as well.
  #
  # Topology segmentation ranks by the declared graph foothold and consumes no
  # random number, so it counts as deterministic here. The optimizer still
  # builds simulation parameters for it from runtime values. Those values are an
  # execution choice, not a study statement, so this contract does not promote
  # them into the definition.

  @type t :: %__MODULE__{
          key: String.t(),
          budget: pos_integer(),
          candidate_action_types: [String.t()],
          require_pre_attack_feasibility: boolean(),
          scoring: Scoring.t() | nil
        }

  embedded_schema do
    field :key, :string
    field :budget, :integer
    field :candidate_action_types, {:array, :string}
    field :require_pre_attack_feasibility, :boolean
    embeds_one :scoring, Scoring, on_replace: :update
  end

  def changeset(strategy, attrs) do
    strategy
    |> cast(attrs, [:key, :budget, :candidate_action_types, :require_pre_attack_feasibility])
    |> cast_embed(:scoring)
    |> validate_required([
      :key,
      :budget,
      :candidate_action_types,
      :require_pre_attack_feasibility
    ])
    |> validate_number(:budget, greater_than: 0)
    |> validate_length(:candidate_action_types, min: 1)
    |> require_scoring_for_simulation()
  end

  @scoring_keys ["simulation_informed", "simulated_annealing"]

  def requires_scoring?(key), do: key in @scoring_keys

  defp require_scoring_for_simulation(changeset) do
    if requires_scoring?(changeset |> get_field(:key)) and
         changeset |> get_field(:scoring) |> is_nil() do
      add_error(changeset, :scoring, "is required for a simulation-backed strategy")
    else
      changeset
    end
  end
end
