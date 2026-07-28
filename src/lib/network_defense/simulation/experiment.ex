defmodule NetworkDefense.Simulation.Experiment do
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Simulation.Seed
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Simulation.Run

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          graph_id: String.t() | nil,
          graph: %Graph{} | Ecto.Association.NotLoaded.t() | nil,
          master_seed: Seed.seed(),
          iteration_count: non_neg_integer(),
          max_attempts: pos_integer(),
          lock_version: integer(),
          runtime_ms: integer(),
          runs: list(Run.t()) | Ecto.Association.NotLoaded.t()
        }

  schema "experiments" do
    belongs_to :graph, Graph

    field :master_seed, :integer
    field :iteration_count, :integer
    field :max_attempts, :integer, default: 1
    field :lock_version, :integer, default: 1
    field :runtime_ms, :integer, default: 0

    has_many :runs, Run

    timestamps(type: :utc_datetime)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [
      :master_seed,
      :iteration_count,
      :max_attempts,
      :lock_version,
      :runtime_ms
    ])
    |> validate_required([:graph_id, :master_seed, :iteration_count, :max_attempts])
    |> validate_number(:master_seed, greater_than_or_equal_to: 0)
    |> validate_number(:iteration_count, greater_than: 0)
    |> validate_number(:max_attempts, greater_than: 0)
    |> foreign_key_constraint(:graph_id)
  end

  def new(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      id: Ecto.UUID.generate(),
      graph_id: Map.get(attrs, :graph_id) || graph_id(Map.get(attrs, :graph)),
      graph: Map.get(attrs, :graph),
      master_seed: Map.fetch!(attrs, :master_seed),
      iteration_count: Map.fetch!(attrs, :iteration_count),
      max_attempts: Map.get(attrs, :max_attempts, 1),
      lock_version: Map.get(attrs, :lock_version, 1),
      runtime_ms: Map.get(attrs, :runtime_ms, 0),
      runs: Map.get(attrs, :runs, [])
    }
  end

  defp graph_id(%Graph{id: id}), do: id
  defp graph_id(_), do: nil
end
