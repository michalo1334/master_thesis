defmodule NetworkDefenseWeb.Web.Contracts.OptimizationReport do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  @enum_values [
    strategy: [:cvss, :simulation_informed, :topology_segmentation, :simulated_annealing]
  ]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :strategy, :string
    field :requested_budget, :integer
    field :used_budget, :integer
    field :runtime_ms, :integer

    embeds_many :actions, NetworkDefenseWeb.Web.Contracts.OptimizationAction, on_replace: :delete
  end

  @type t :: %__MODULE__{
          strategy: String.t(),
          requested_budget: integer(),
          used_budget: integer(),
          runtime_ms: integer(),
          actions: [NetworkDefenseWeb.Web.Contracts.OptimizationAction.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:strategy, :requested_budget, :used_budget, :runtime_ms])
    |> cast_embed(:actions)
    |> validate_required([:strategy, :requested_budget, :used_budget, :runtime_ms])
    |> validate_inclusion(
      :strategy,
      @enum_values |> Keyword.fetch!(:strategy) |> Enum.map(&Atom.to_string/1)
    )
  end
end
