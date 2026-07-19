defmodule NetworkDefense.Simulation.IterationStep do
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Actions.Action
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Simulation.State
  alias NetworkDefense.Simulation.Types.Action, as: ActionType
  alias NetworkDefense.Simulation.Types.AttackerState, as: AttackerStateType
  alias NetworkDefense.Simulation.Types.Seed

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          simulation_id: String.t() | nil,
          index: non_neg_integer(),
          attempted_action: Action.t() | nil,
          success?: boolean(),
          attacker_state: AttackerState.t(),
          seed: tuple()
        }

  schema "iteration_steps" do
    belongs_to :simulation, State

    field :index, :integer
    field :attempted_action, ActionType
    field :success?, :boolean, source: :success
    field :attacker_state, AttackerStateType
    field :seed, Seed

    timestamps(type: :utc_datetime)
  end

  def changeset(step, attrs) do
    step
    |> cast(attrs, [:index, :attempted_action, :success?, :attacker_state, :seed])
    |> validate_required([:simulation_id, :index, :success?, :attacker_state, :seed])
    |> validate_number(:index, greater_than: 0)
    |> foreign_key_constraint(:simulation_id)
    |> unique_constraint([:simulation_id, :index])
  end

  def new(opts \\ []), do: struct!(__MODULE__, opts)
end
