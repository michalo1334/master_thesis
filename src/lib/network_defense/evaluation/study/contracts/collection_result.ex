defmodule NetworkDefense.Evaluation.Study.Contracts.CollectionResult do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  @type t :: %__MODULE__{
          collection_item_id: String.t(),
          replica_position: -1..4,
          item_position: non_neg_integer(),
          optimization_run_id: String.t(),
          experiment_id: String.t(),
          completed_trials: non_neg_integer(),
          total_trials: pos_integer()
        }

  @fields [
    :collection_item_id,
    :replica_position,
    :item_position,
    :optimization_run_id,
    :experiment_id,
    :completed_trials,
    :total_trials
  ]

  embedded_schema do
    field :collection_item_id, :string
    field :replica_position, :integer
    field :item_position, :integer
    field :optimization_run_id, :string
    field :experiment_id, :string
    field :completed_trials, :integer
    field :total_trials, :integer
  end

  @spec new(map()) :: {:ok, t()} | :error
  def new(attrs) when is_map(attrs) do
    case %__MODULE__{} |> changeset(attrs) |> apply_action(:validate) do
      {:ok, result} -> {:ok, result}
      {:error, _changeset} -> :error
    end
  end

  def new(_attrs), do: :error

  def changeset(result, attrs) do
    result
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:replica_position, greater_than_or_equal_to: -1, less_than_or_equal_to: 4)
    |> validate_number(:item_position, greater_than_or_equal_to: 0)
    |> validate_number(:completed_trials, greater_than_or_equal_to: 0)
    |> validate_number(:total_trials, greater_than: 0)
    |> Contracts.validate_uuid(:collection_item_id)
    |> Contracts.validate_uuid(:optimization_run_id)
    |> Contracts.validate_uuid(:experiment_id)
  end
end
