defmodule NetworkDefense.Optimization.OptimizationRun do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Graph.GraphRevision
  alias NetworkDefense.Optimization.OptimizationAction

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          graph_revision_id: String.t() | nil,
          output_graph_revision_id: String.t() | nil,
          actions: list(OptimizationAction.t()) | Ecto.Association.NotLoaded.t(),
          strategy: String.t() | nil,
          requested_budget: integer() | nil,
          used_budget: integer() | nil,
          runtime_ms: integer() | nil,
          status: String.t() | nil
        }

  schema "optimization_runs" do
    belongs_to :graph_revision, GraphRevision
    belongs_to :output_graph_revision, GraphRevision
    has_many :actions, OptimizationAction, foreign_key: :optimization_run_id

    field :strategy, :string
    field :requested_budget, :integer
    field :used_budget, :integer, default: 0
    field :runtime_ms, :integer, default: 0
    field :status, :string, default: "running"

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :graph_revision_id,
      :output_graph_revision_id,
      :strategy,
      :requested_budget,
      :used_budget,
      :runtime_ms,
      :status
    ])
    |> validate_required([:graph_revision_id, :strategy, :requested_budget])
    |> validate_number(:requested_budget, greater_than: 0)
    |> validate_number(:used_budget, greater_than_or_equal_to: 0)
    |> validate_number(:runtime_ms, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, ["running", "completed", "failed"])
    |> validate_output_revision()
    |> foreign_key_constraint(:graph_revision_id)
    |> foreign_key_constraint(:output_graph_revision_id)
  end

  def new(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      id: Ecto.UUID.generate(),
      graph_revision_id: Map.get(attrs, :graph_revision_id),
      strategy: Map.fetch!(attrs, :strategy),
      requested_budget: Map.fetch!(attrs, :requested_budget),
      used_budget: Map.get(attrs, :used_budget, 0),
      runtime_ms: Map.get(attrs, :runtime_ms, 0),
      status: Map.get(attrs, :status, "running")
    }
  end

  defp validate_output_revision(changeset) do
    if get_field(changeset, :status) == "completed" do
      validate_required(changeset, :output_graph_revision_id)
    else
      changeset
    end
  end
end
