defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.DefinitionInput do
  @moduledoc false
  # Ecto casts numeric form text at the dashboard boundary.
  # Successful reads use the strict Definition contract.
  use NetworkDefenseWeb.StudyContract, enums: [:rules, :allowed_action_types]

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
    embeds_many :tiers, NetworkDefenseWeb.Contracts.Dashboard.Study.TierInput, on_replace: :delete

    embeds_many :candidates, NetworkDefenseWeb.Contracts.Dashboard.Study.CandidateInput,
      on_replace: :delete

    field :extra_pool_plans, :integer
    field :extra_pool_attacks, :integer
    field :outer_subsamples, :integer
    field :target_half_width, :float
    field :guard_quantile, :float
  end

  @type t :: %__MODULE__{
          study_id: String.t(),
          revision: integer() | String.t(),
          seed: String.t(),
          family_id: String.t(),
          family_alpha: float() | String.t(),
          confidence_level: float() | String.t(),
          feasibility: String.t(),
          allowed_action_types: [String.t()],
          iterations_per_run: integer() | String.t(),
          max_attempts: integer() | String.t(),
          rules: [String.t()],
          tiers: [NetworkDefenseWeb.Contracts.Dashboard.Study.TierInput.t()],
          candidates: [NetworkDefenseWeb.Contracts.Dashboard.Study.CandidateInput.t()],
          extra_pool_plans: integer() | String.t(),
          extra_pool_attacks: integer() | String.t(),
          outer_subsamples: integer() | String.t(),
          target_half_width: float() | String.t(),
          guard_quantile: float() | String.t()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
