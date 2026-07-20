defmodule NetworkDefense.Simulation.MultiState do
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Simulation.State
  alias NetworkDefense.Simulation.Types.AttackerState, as: AttackerStateType

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          graph_id: String.t() | nil,
          graph: %Graph{} | Ecto.Association.NotLoaded.t() | nil,
          seed: integer(),
          iteration_count: non_neg_integer(),
          simulation_count: non_neg_integer(),
          initial_attacker_state: AttackerState.t(),
          lock_version: integer(),
          runtime_ms: integer(),
          simulations: list(State.t()) | Ecto.Association.NotLoaded.t()
        }

  schema "multi_states" do
    belongs_to :graph, Graph

    field :seed, :integer
    field :iteration_count, :integer
    field :simulation_count, :integer, default: 1
    field :initial_attacker_state, AttackerStateType
    field :lock_version, :integer, default: 1
    field :runtime_ms, :integer, default: 0

    has_many :simulations, State

    timestamps(type: :utc_datetime)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [
      :seed,
      :iteration_count,
      :simulation_count,
      :initial_attacker_state,
      :lock_version,
      :runtime_ms
    ])
    |> validate_required([:graph_id, :seed, :iteration_count, :initial_attacker_state])
    |> validate_number(:seed, greater_than_or_equal_to: 0)
    |> validate_number(:iteration_count, greater_than: 0)
    |> foreign_key_constraint(:graph_id)
  end

  def new(opts \\ []) do
    struct!(
      __MODULE__,
      Keyword.merge(
        [
          id: Ecto.UUID.generate(),
          seed: 0,
          iteration_count: 1000
        ],
        opts
      )
    )
    |> set_graph_id()
  end

  def set_graph_id(%__MODULE__{graph: %Graph{id: graph_id}} = state) do
    %{state | graph_id: graph_id}
  end

  def set_graph_id(state), do: state
end
