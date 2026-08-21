defmodule NetworkDefense.Optimization.OptimizationRun do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Evaluation.EvaluationRun
  alias NetworkDefense.Graph.GraphRevision
  alias NetworkDefense.Optimization.OptimizationAction

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          graph_revision_id: String.t() | nil,
          output_graph_revision_id: String.t() | nil,
          evaluation_run_id: String.t() | nil,
          actions: list(OptimizationAction.t()) | Ecto.Association.NotLoaded.t(),
          strategy: String.t() | nil,
          requested_budget: integer() | nil,
          used_budget: integer() | nil,
          runtime_ms: integer() | nil,
          status: String.t() | nil,
          seed: integer() | nil,
          selection_seed: integer() | nil,
          simulation_config: map() | nil
        }

  schema "optimization_runs" do
    belongs_to :graph_revision, GraphRevision
    belongs_to :output_graph_revision, GraphRevision
    belongs_to :evaluation_run, EvaluationRun
    has_many :actions, OptimizationAction, foreign_key: :optimization_run_id

    field :strategy, :string
    field :requested_budget, :integer
    field :used_budget, :integer, default: 0
    field :runtime_ms, :integer, default: 0
    field :status, :string, default: "running"
    field :seed, :integer
    field :selection_seed, :integer
    field :simulation_config, :map

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :graph_revision_id,
      :output_graph_revision_id,
      :evaluation_run_id,
      :strategy,
      :requested_budget,
      :used_budget,
      :runtime_ms,
      :status,
      :seed,
      :selection_seed,
      :simulation_config
    ])
    |> validate_required([:graph_revision_id, :strategy, :requested_budget])
    |> validate_number(:requested_budget, greater_than: 0)
    |> validate_number(:used_budget, greater_than_or_equal_to: 0)
    |> validate_number(:runtime_ms, greater_than_or_equal_to: 0)
    |> validate_number(:seed, greater_than_or_equal_to: 0)
    |> validate_number(:selection_seed, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, ["running", "completed", "failed"])
    |> validate_output_revision()
    |> foreign_key_constraint(:graph_revision_id)
    |> foreign_key_constraint(:output_graph_revision_id)
    |> foreign_key_constraint(:evaluation_run_id)
    |> unique_constraint([:evaluation_run_id, :strategy, :requested_budget, :selection_seed],
      name: :optimization_runs_evaluation_plan_unique
    )
  end

  def new(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      id: Ecto.UUID.generate(),
      graph_revision_id: Map.get(attrs, :graph_revision_id),
      evaluation_run_id: Map.get(attrs, :evaluation_run_id),
      strategy: Map.fetch!(attrs, :strategy),
      requested_budget: Map.fetch!(attrs, :requested_budget),
      used_budget: Map.get(attrs, :used_budget, 0),
      runtime_ms: Map.get(attrs, :runtime_ms, 0),
      status: Map.get(attrs, :status, "running"),
      seed: Map.get(attrs, :seed),
      selection_seed: Map.get(attrs, :selection_seed),
      simulation_config: Map.get(attrs, :simulation_config)
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
