defmodule NetworkDefense.Optimization.OptimizationAction do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Optimization.OptimizationRun

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          optimization_run_id: String.t() | nil,
          position: integer() | nil,
          action_type: String.t() | nil,
          target_id: String.t() | nil,
          cost: integer() | nil
        }

  schema "optimization_actions" do
    belongs_to :optimization_run, OptimizationRun

    field :position, :integer
    field :action_type, :string
    field :target_id, :binary_id
    field :cost, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(action, attrs) do
    action
    |> cast(attrs, [
      :optimization_run_id,
      :position,
      :action_type,
      :target_id,
      :cost
    ])
    |> validate_required([
      :optimization_run_id,
      :position,
      :action_type,
      :target_id,
      :cost
    ])
    |> validate_number(:position, greater_than: 0)
    |> validate_number(:cost, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:optimization_run_id)
    |> unique_constraint([:optimization_run_id, :position],
      name: :optimization_actions_optimization_run_id_position_index
    )
  end
end
