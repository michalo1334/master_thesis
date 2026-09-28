defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisMetadata do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisRuntimeSummary

  embedded_schema do
    field :manifest_id, :string
    field :schema_version, :integer
    field :model_version, :string
    field :model_variants, {:array, :map}
    field :command_mode, :string
    field :study_id, :string
    field :specification_version, :integer
    field :family_scope, :string
    field :family_size, :integer
    field :tier_labels, {:array, :string}
    field :expected_family, :map
    field :multiplicity_correction, :string
    field :uncertainty_sources, {:array, :string}
    field :recommended_plan_selection_seed_count, :integer
    field :recommended_attacks_per_plan, :integer
    field :insufficient_pilot, :boolean
    field :input_trial_count, :integer
    field :declared_plan_trial_count, :integer
    field :simulator_only_uncertainty, :boolean
    field :analysis_runtime_seconds, :float
    field :input_hashes, :map
    field :checksums_hash, :string
    field :analysis_configuration, :map
    field :estimand_note, :string
    field :package_version, :string
    field :dependencies, :map
    embeds_one :runtime_summary, EvaluationAnalysisRuntimeSummary
  end

  @type t :: %__MODULE__{
          manifest_id: String.t() | nil,
          schema_version: integer() | nil,
          model_version: String.t() | nil,
          model_variants: [map()] | nil,
          command_mode: String.t(),
          study_id: String.t() | nil,
          specification_version: integer() | nil,
          family_scope: String.t() | nil,
          family_size: integer() | nil,
          tier_labels: [String.t()] | nil,
          expected_family: map() | nil,
          multiplicity_correction: String.t() | nil,
          uncertainty_sources: [String.t()] | nil,
          recommended_plan_selection_seed_count: integer() | nil,
          recommended_attacks_per_plan: integer() | nil,
          insufficient_pilot: boolean() | nil,
          input_trial_count: integer() | nil,
          declared_plan_trial_count: integer() | nil,
          simulator_only_uncertainty: boolean() | nil,
          analysis_runtime_seconds: float() | nil,
          input_hashes: map() | nil,
          checksums_hash: String.t() | nil,
          analysis_configuration: map() | nil,
          estimand_note: String.t() | nil,
          package_version: String.t() | nil,
          dependencies: map() | nil,
          runtime_summary: EvaluationAnalysisRuntimeSummary.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :manifest_id,
      :schema_version,
      :model_version,
      :model_variants,
      :command_mode,
      :study_id,
      :specification_version,
      :family_scope,
      :family_size,
      :tier_labels,
      :expected_family,
      :multiplicity_correction,
      :uncertainty_sources,
      :recommended_plan_selection_seed_count,
      :recommended_attacks_per_plan,
      :insufficient_pilot,
      :input_trial_count,
      :declared_plan_trial_count,
      :simulator_only_uncertainty,
      :analysis_runtime_seconds,
      :input_hashes,
      :checksums_hash,
      :analysis_configuration,
      :estimand_note,
      :package_version,
      :dependencies
    ])
    |> cast_embed(:runtime_summary)
    |> validate_metadata_identity()
  end

  defp validate_metadata_identity(changeset) do
    if get_field(changeset, :family_scope) == "study" do
      validate_required(changeset, [
        :study_id,
        :specification_version,
        :family_scope,
        :family_size,
        :command_mode
      ])
    else
      validate_required(changeset, [
        :manifest_id,
        :schema_version,
        :model_version,
        :command_mode,
        :runtime_summary
      ])
    end
  end
end
