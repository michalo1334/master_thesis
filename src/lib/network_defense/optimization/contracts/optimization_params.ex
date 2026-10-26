defmodule NetworkDefense.Optimization.Contracts.OptimizationParams do
  @moduledoc false

  alias Ecto.Changeset
  alias NetworkDefense.DefenseActions.Registry, as: DefenseActionsRegistry
  alias NetworkDefense.Optimization.Contracts.SimulationSettings

  use NetworkDefense.Contracts, category: :optimization

  @strategies [
    :null,
    :random,
    :cvss,
    :simulation_informed,
    :topology_segmentation,
    :simulated_annealing
  ]

  @type strategy ::
          :null
          | :random
          | :cvss
          | :simulation_informed
          | :topology_segmentation
          | :simulated_annealing

  @foothold_strategies [:simulation_informed, :topology_segmentation, :simulated_annealing]
  @scoring_strategies [:simulation_informed, :simulated_annealing]

  @enum_values [
    strategy: @strategies,
    candidate_action_types: DefenseActionsRegistry.values()
  ]

  def contract_meta, do: %{enum_values: @enum_values}

  @doc "Every accepted optimization strategy."
  @spec strategy_values() :: [strategy()]
  def strategy_values, do: @strategies

  def requires_simulation_params?(strategy), do: strategy in @scoring_strategies
  def requires_initial_foothold?(strategy), do: strategy in @foothold_strategies

  embedded_schema do
    field :strategy, Ecto.Enum, values: @strategies
    field :budget, :integer
    field :seed, :integer
    field :candidate_action_types, {:array, Ecto.Enum}, values: DefenseActionsRegistry.values()
    field :require_pre_attack_feasibility, :boolean
    field :initial_foothold_node_id, :string
    embeds_one :simulation_params, SimulationSettings, on_replace: :update
  end

  @type t :: %__MODULE__{
          strategy: strategy(),
          budget: pos_integer(),
          seed: non_neg_integer(),
          candidate_action_types: [DefenseActionsRegistry.action_type()],
          require_pre_attack_feasibility: boolean(),
          initial_foothold_node_id: String.t() | nil,
          simulation_params: SimulationSettings.t() | nil
        }

  # The scalar fields are cast first. The scoring block is then cast for a
  # strategy that simulates candidates, rejected for a strategy that does not,
  # and ignored for a strategy that the scalar cast already rejected, so one
  # invalid value produces one error.
  def changeset(schema, attrs) do
    changeset =
      schema
      |> cast(attrs, [
        :strategy,
        :budget,
        :seed,
        :candidate_action_types,
        :require_pre_attack_feasibility,
        :initial_foothold_node_id
      ])
      |> validate_required([
        :strategy,
        :budget,
        :seed,
        :candidate_action_types,
        :require_pre_attack_feasibility
      ])
      |> validate_number(:budget, greater_than: 0)
      |> validate_number(:seed, greater_than_or_equal_to: 0)
      |> validate_length(:candidate_action_types, min: 1)
      |> Contracts.validate_uuid(:initial_foothold_node_id)

    changeset
    |> cast_scoring(attrs)
    |> require_foothold()
  end

  defp cast_scoring(changeset, attrs) do
    case Changeset.get_field(changeset, :strategy) do
      strategy when strategy in @scoring_strategies ->
        cast_embed(changeset, :simulation_params, required: true)

      strategy when strategy in @strategies ->
        reject_scoring(changeset, attrs)

      nil ->
        changeset
    end
  end

  defp reject_scoring(changeset, attrs) do
    if scoring_supplied?(attrs) do
      Changeset.add_error(changeset, :simulation_params, "is not supported for this strategy")
    else
      changeset
    end
  end

  defp scoring_supplied?(attrs) when is_map(attrs) do
    normalized_attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
    not is_nil(Map.get(normalized_attrs, "simulation_params"))
  end

  defp scoring_supplied?(_attrs), do: false

  defp require_foothold(changeset) do
    if requires_initial_foothold?(Changeset.get_field(changeset, :strategy)) and
         is_nil(Changeset.get_field(changeset, :initial_foothold_node_id)) do
      Changeset.add_error(changeset, :initial_foothold_node_id, "is required")
    else
      changeset
    end
  end
end
