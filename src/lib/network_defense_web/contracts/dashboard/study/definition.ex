defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Definition do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  def contract_meta do
    %{
      enum_values: [
        rules: NetworkDefense.Rules.Registry.values(),
        allowed_action_types: NetworkDefense.DefenseActions.Registry.values(),
        feasibility: [:required, :unrestricted]
      ]
    }
  end

  embedded_schema do
    field :study_id, :string
    field :revision, :integer
    field :seed, :string
    field :family_id, :string
    field :family_alpha, :float
    field :confidence_level, :float
    field :feasibility, :string
    field :allowed_action_types, {:array, :string}
    field :iterations_per_run, :integer
    field :max_attempts, :integer
    field :rules, {:array, :string}
    embeds_many :tiers, NetworkDefenseWeb.Contracts.Dashboard.Study.Tier, on_replace: :delete

    embeds_many :candidates, NetworkDefenseWeb.Contracts.Dashboard.Study.Candidate,
      on_replace: :delete

    field :extra_pool_plans, :integer
    field :extra_pool_attacks, :integer
    field :outer_subsamples, :integer
    field :target_half_width, :float
    field :guard_quantile, :float
  end

  @type t :: %__MODULE__{
          study_id: String.t(),
          revision: non_neg_integer(),
          seed: String.t(),
          family_id: String.t(),
          family_alpha: float(),
          confidence_level: float(),
          feasibility: String.t(),
          allowed_action_types: [String.t()],
          iterations_per_run: non_neg_integer(),
          max_attempts: non_neg_integer(),
          rules: [String.t()],
          tiers: [NetworkDefenseWeb.Contracts.Dashboard.Study.Tier.t()],
          candidates: [NetworkDefenseWeb.Contracts.Dashboard.Study.Candidate.t()],
          extra_pool_plans: non_neg_integer(),
          extra_pool_attacks: non_neg_integer(),
          outer_subsamples: non_neg_integer(),
          target_half_width: float(),
          guard_quantile: float()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
