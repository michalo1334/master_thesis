defmodule NetworkDefenseWeb.Web.Contracts.OptimizationReport do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  @enum_values [
    strategy: [:cvss, :simulation_informed, :topology_segmentation, :simulated_annealing],
    objective: [:blast_radius, :mission_impact]
  ]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :strategy, :string
    field :objective, :string
    field :requested_budget, :integer
    field :used_budget, :integer
    field :runtime_ms, :integer

    embeds_many :actions, NetworkDefenseWeb.Web.Contracts.OptimizationAction, on_replace: :delete
  end

  @type t :: %__MODULE__{
          strategy: String.t(),
          objective: String.t(),
          requested_budget: integer(),
          used_budget: integer(),
          runtime_ms: integer(),
          actions: [NetworkDefenseWeb.Web.Contracts.OptimizationAction.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:strategy, :objective, :requested_budget, :used_budget, :runtime_ms])
    |> cast_embed(:actions)
    |> validate_required([:strategy, :objective, :requested_budget, :used_budget, :runtime_ms])
    |> validate_inclusion(
      :strategy,
      @enum_values |> Keyword.fetch!(:strategy) |> Enum.map(&Atom.to_string/1)
    )
    |> validate_inclusion(
      :objective,
      @enum_values |> Keyword.fetch!(:objective) |> Enum.map(&Atom.to_string/1)
    )
  end
end
