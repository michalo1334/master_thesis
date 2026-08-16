defmodule NetworkDefense.Simulation.Experiment do
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Simulation.Seed
  alias NetworkDefense.Graph.{Graph, GraphRevision}
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Workflows.WorkflowRun

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          graph_revision_id: String.t() | nil,
          analysis_id: String.t() | nil,
          graph: %Graph{} | Ecto.Association.NotLoaded.t() | nil,
          master_seed: Seed.seed(),
          iteration_count: non_neg_integer(),
          max_attempts: pos_integer(),
          runtime_ms: integer(),
          total_trials: pos_integer(),
          completed_trials: non_neg_integer(),
          status: String.t(),
          initial_foothold_node_id: String.t() | nil,
          runs: list(Run.t()) | Ecto.Association.NotLoaded.t()
        }

  schema "experiments" do
    belongs_to :graph_revision, GraphRevision
    belongs_to :analysis, WorkflowRun
    field :graph, :any, virtual: true

    field :master_seed, :integer
    field :iteration_count, :integer
    field :max_attempts, :integer, default: 1
    field :runtime_ms, :integer, default: 0
    field :total_trials, :integer, default: 0
    field :completed_trials, :integer, default: 0
    field :status, :string, default: "completed"
    field :initial_foothold_node_id, :binary_id

    has_many :runs, Run

    timestamps(type: :utc_datetime)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [
      :master_seed,
      :iteration_count,
      :max_attempts,
      :runtime_ms,
      :total_trials,
      :completed_trials,
      :status,
      :initial_foothold_node_id,
      :analysis_id
    ])
    |> validate_required([
      :graph_revision_id,
      :master_seed,
      :iteration_count,
      :max_attempts,
      :total_trials,
      :completed_trials,
      :status
    ])
    |> validate_number(:master_seed, greater_than_or_equal_to: 0)
    |> validate_number(:iteration_count, greater_than: 0)
    |> validate_number(:max_attempts, greater_than: 0)
    |> validate_number(:total_trials, greater_than: 0)
    |> validate_number(:completed_trials, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, ["running", "failed", "completed"])
    |> foreign_key_constraint(:graph_revision_id)
    |> foreign_key_constraint(:analysis_id)
  end

  def new(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      id: Ecto.UUID.generate(),
      graph_revision_id:
        Map.get(attrs, :graph_revision_id) || graph_revision_id(Map.get(attrs, :graph)),
      analysis_id: Map.get(attrs, :analysis_id),
      graph: Map.get(attrs, :graph),
      master_seed: Map.fetch!(attrs, :master_seed),
      iteration_count: Map.fetch!(attrs, :iteration_count),
      max_attempts: Map.get(attrs, :max_attempts, 1),
      runtime_ms: Map.get(attrs, :runtime_ms, 0),
      total_trials: Map.get(attrs, :total_trials, length(Map.get(attrs, :runs, []))),
      completed_trials: Map.get(attrs, :completed_trials, 0),
      status: Map.get(attrs, :status, "running"),
      initial_foothold_node_id: Map.get(attrs, :initial_foothold_node_id),
      runs: Map.get(attrs, :runs, [])
    }
  end

  defp graph_revision_id(%Graph{revision_id: id}), do: id
  defp graph_revision_id(_), do: nil
end
