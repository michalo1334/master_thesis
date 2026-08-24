defmodule NetworkDefenseWeb.Web.Contracts.EvaluationAnalysisMetadata do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :manifest_id, :string
    field :schema_version, :integer
    field :model_version, :string
    field :command_mode, :string
    field :pilot_all_pass, :boolean
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
  end

  @type t :: %__MODULE__{
          manifest_id: String.t(),
          schema_version: integer(),
          model_version: String.t(),
          command_mode: String.t(),
          pilot_all_pass: boolean() | nil,
          input_trial_count: integer() | nil,
          declared_plan_trial_count: integer() | nil,
          simulator_only_uncertainty: boolean() | nil,
          analysis_runtime_seconds: float() | nil,
          input_hashes: map() | nil,
          checksums_hash: String.t() | nil,
          analysis_configuration: map() | nil,
          estimand_note: String.t() | nil,
          package_version: String.t() | nil,
          dependencies: map() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :manifest_id,
      :schema_version,
      :model_version,
      :command_mode,
      :pilot_all_pass,
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
    |> validate_required([:manifest_id, :schema_version, :model_version, :command_mode])
  end
end
