defmodule NetworkDefense.Optimization.Contracts.OptimizationParams do
  @moduledoc false

  alias Ecto.Changeset
  alias NetworkDefense.Simulation.Contracts.SimulationParams

  use NetworkDefense.Contracts, category: :optimization

  @enum_values [
    strategy: [:cvss, :simulation_informed, :topology_segmentation, :simulated_annealing],
    objective: [:blast_radius, :mission_impact]
  ]
  @baseline_strategies ["cvss", "topology_segmentation"]
  @simulation_strategies ["simulation_informed", "topology_segmentation", "simulated_annealing"]

  def contract_meta, do: %{enum_values: @enum_values}

  def requires_simulation_params?(strategy), do: strategy in @simulation_strategies

  embedded_schema do
    field :strategy, :string
    field :objective, :string, default: "blast_radius"
    field :budget, :integer
    embeds_one :simulation_params, SimulationParams, on_replace: :update
  end

  @type t :: %__MODULE__{
          strategy: String.t(),
          objective: String.t(),
          budget: pos_integer(),
          simulation_params: SimulationParams.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:strategy, :objective, :budget])
    |> cast_embed(:simulation_params)
    |> validate_required([:strategy, :objective, :budget])
    |> validate_inclusion(
      :strategy,
      @enum_values |> Keyword.fetch!(:strategy) |> Enum.map(&Atom.to_string/1)
    )
    |> validate_inclusion(
      :objective,
      @enum_values |> Keyword.fetch!(:objective) |> Enum.map(&Atom.to_string/1)
    )
    |> validate_number(:budget, greater_than: 0)
    |> validate_objective_strategy()
    |> require_simulation_params()
  end

  defp validate_objective_strategy(changeset) do
    if Changeset.get_field(changeset, :objective) == "mission_impact" and
         Changeset.get_field(changeset, :strategy) in @baseline_strategies do
      Changeset.add_error(changeset, :objective, "is unsupported by the selected strategy")
    else
      changeset
    end
  end

  defp require_simulation_params(changeset) do
    if requires_simulation_params?(Changeset.get_field(changeset, :strategy)) and
         is_nil(Changeset.get_field(changeset, :simulation_params)) do
      Changeset.add_error(changeset, :simulation_params, "is required")
    else
      changeset
    end
  end
end
