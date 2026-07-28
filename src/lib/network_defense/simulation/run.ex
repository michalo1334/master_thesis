defmodule NetworkDefense.Simulation.Run do
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Rules.Rule
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.Experiment

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          graph_id: String.t() | nil,
          graph: %Graph{} | Ecto.Association.NotLoaded.t() | nil,
          seed: integer(),
          initial_attacker_state: AttackerState.t(),
          rules: list(Rule.t()),
          iterations: list(IterationStep.t()) | Ecto.Association.NotLoaded.t(),
          experiment_id: String.t() | nil,
          experiment: Experiment.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "simulation_runs" do
    belongs_to :graph, Graph
    belongs_to :experiment, Experiment

    field :seed, :integer
    embeds_one :initial_attacker_state, AttackerState, on_replace: :update
    field :rules, :any, virtual: true, default: []

    has_many :iterations, IterationStep, foreign_key: :run_id

    timestamps(type: :utc_datetime)
  end

  def changeset(state, attrs) do
    changeset =
      state
      |> cast(attrs, [:seed, :experiment_id])

    changeset =
      case Map.get(attrs, :initial_attacker_state) do
        %AttackerState{} = attacker_state ->
          put_embed(changeset, :initial_attacker_state, attacker_state)

        _ ->
          changeset
      end

    changeset
    |> validate_required([:graph_id, :seed, :initial_attacker_state])
    |> validate_number(:seed, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:graph_id)
    |> foreign_key_constraint(:experiment_id)
  end

  def new(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      id: Ecto.UUID.generate(),
      graph_id: Map.get(attrs, :graph_id) || graph_id(Map.get(attrs, :graph)),
      graph: Map.get(attrs, :graph),
      seed: Map.get(attrs, :seed, 0),
      initial_attacker_state: Map.fetch!(attrs, :initial_attacker_state),
      rules: Map.get(attrs, :rules, []),
      iterations: Map.get(attrs, :iterations, []),
      experiment_id: Map.get(attrs, :experiment_id)
    }
  end

  def current_iteration(%__MODULE__{iterations: []}), do: nil
  def current_iteration(%__MODULE__{iterations: [iteration | _]}), do: iteration

  def current_attacker_state(%__MODULE__{} = state) do
    case current_iteration(state) do
      nil -> state.initial_attacker_state
      iteration -> iteration.attacker_state
    end
  end

  def current_seed(%__MODULE__{seed: seed}), do: seed

  def add_iteration_step(
        %__MODULE__{iterations: iterations} = state,
        %IterationStep{} = iteration
      )
      when is_list(iterations) do
    %{state | iterations: [iteration | iterations]}
  end

  defp graph_id(%Graph{id: id}), do: id
  defp graph_id(_), do: nil
end
