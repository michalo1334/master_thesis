defmodule NetworkDefense.Evaluation.Study.Contracts.CollectionWorkItem do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.{Comparison, Strategy}

  @type side :: :alternative | :reference

  @type t :: %__MODULE__{
          item_position: non_neg_integer(),
          replica_position: -1..4,
          comparison_position: non_neg_integer(),
          comparison: Comparison.t(),
          side: side(),
          graph_revision_id: String.t(),
          initial_foothold_node_id: String.t(),
          strategy: Strategy.t(),
          budget: pos_integer(),
          plan_position: non_neg_integer(),
          selection_seed: non_neg_integer(),
          evaluation_root: non_neg_integer(),
          attack_count: pos_integer(),
          iterations_per_run: pos_integer(),
          max_attempts: pos_integer()
        }

  @fields [
    :item_position,
    :replica_position,
    :comparison_position,
    :side,
    :graph_revision_id,
    :initial_foothold_node_id,
    :budget,
    :plan_position,
    :selection_seed,
    :evaluation_root,
    :attack_count,
    :iterations_per_run,
    :max_attempts
  ]

  @positions [
    :item_position,
    :comparison_position,
    :plan_position,
    :selection_seed,
    :evaluation_root
  ]

  embedded_schema do
    field :item_position, :integer
    field :replica_position, :integer
    field :comparison_position, :integer
    embeds_one :comparison, Comparison, on_replace: :update
    field :side, Ecto.Enum, values: [:alternative, :reference]
    field :graph_revision_id, :string
    field :initial_foothold_node_id, :string
    embeds_one :strategy, Strategy, on_replace: :update
    field :budget, :integer
    field :plan_position, :integer
    field :selection_seed, :integer
    field :evaluation_root, :integer
    field :attack_count, :integer
    field :iterations_per_run, :integer
    field :max_attempts, :integer
  end

  @spec new(map()) :: {:ok, t()} | :error
  def new(attrs) when is_map(attrs) do
    %__MODULE__{} |> changeset(attrs) |> Contracts.validate_or_error()
  end

  def new(_attrs), do: :error

  def changeset(item, attrs) do
    item
    |> cast(attrs, @fields)
    |> cast_embed(:comparison, required: true)
    |> cast_embed(:strategy, required: true)
    |> validate_required(@fields)
    |> validate_number(:budget, greater_than: 0)
    |> validate_number(:attack_count, greater_than: 0)
    |> validate_number(:iterations_per_run, greater_than: 0)
    |> validate_number(:max_attempts, greater_than: 0)
    |> validate_positions()
    |> validate_number(:replica_position, greater_than_or_equal_to: -1, less_than_or_equal_to: 4)
    |> Contracts.validate_uuid(:graph_revision_id)
    |> Contracts.validate_uuid(:initial_foothold_node_id)
  end

  defp validate_positions(changeset) do
    Enum.reduce(@positions, changeset, fn field, acc ->
      validate_number(acc, field, greater_than_or_equal_to: 0)
    end)
  end
end
