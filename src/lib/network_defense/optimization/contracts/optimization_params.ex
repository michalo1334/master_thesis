defmodule NetworkDefense.Optimization.Contracts.OptimizationParams do
  @moduledoc false

  alias Ecto.Changeset
  alias NetworkDefense.Simulation.Contracts.SimulationParams

  use NetworkDefense.Contracts, category: :optimization

  @enum_values strategy: [
                 :cvss,
                 :simulation_informed,
                 :topology_segmentation,
                 :simulated_annealing
               ]
  @simulation_strategies ["simulation_informed", "topology_segmentation", "simulated_annealing"]

  def contract_meta, do: %{enum_values: @enum_values}

  def requires_simulation_params?(strategy), do: strategy in @simulation_strategies

  embedded_schema do
    field :strategy, :string
    field :budget, :integer
    embeds_one :simulation_params, SimulationParams, on_replace: :update
  end

  @type t :: %__MODULE__{
          strategy: String.t(),
          budget: pos_integer(),
          simulation_params: SimulationParams.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:strategy, :budget])
    |> cast_embed(:simulation_params)
    |> validate_required([:strategy, :budget])
    |> validate_inclusion(
      :strategy,
      @enum_values |> Keyword.fetch!(:strategy) |> Enum.map(&Atom.to_string/1)
    )
    |> validate_number(:budget, greater_than: 0)
    |> require_simulation_params()
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
