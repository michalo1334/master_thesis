defmodule NetworkDefense.Simulation.Run do
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Rules.Rule
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Types.AttackerState, as: AttackerStateType

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          graph_id: String.t() | nil,
          graph: %Graph{} | Ecto.Association.NotLoaded.t() | nil,
          initial_seed: integer(),
          initial_attacker_state: AttackerState.t(),
          iteration_count: non_neg_integer(),
          rules: list(Rule.t()),
          iterations: list(IterationStep.t()) | Ecto.Association.NotLoaded.t(),
          experiment_id: String.t() | nil,
          experiment: Experiment.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "simulation_runs" do
    belongs_to :graph, Graph
    belongs_to :experiment, Experiment

    field :initial_seed, :integer, default: 0
    field :initial_attacker_state, AttackerStateType
    field :iteration_count, :integer, default: 1000
    field :rules, :any, virtual: true, default: []

    has_many :iterations, IterationStep, foreign_key: :run_id

    timestamps(type: :utc_datetime)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [
      :initial_seed,
      :initial_attacker_state,
      :iteration_count,
      :experiment_id
    ])
    |> validate_required([:graph_id, :initial_seed, :initial_attacker_state, :iteration_count])
    |> validate_number(:initial_seed, greater_than_or_equal_to: 0)
    |> validate_number(:iteration_count, greater_than: 0)
    |> foreign_key_constraint(:graph_id)
  end

  def new(opts \\ []) do
    state =
      struct!(
        __MODULE__,
        Keyword.merge(
          [
            id: Ecto.UUID.generate(),
            initial_seed: 0,
            iteration_count: 1000,
            iterations: [],
            rules: []
          ],
          opts
        )
      )

    %{state | graph_id: state.graph_id || graph_id(state.graph)}
  end

  def current_iteration(%__MODULE__{iterations: []}), do: nil
  def current_iteration(%__MODULE__{iterations: [iteration | _]}), do: iteration

  def current_attacker_state(%__MODULE__{} = state) do
    case current_iteration(state) do
      nil -> state.initial_attacker_state
      iteration -> iteration.attacker_state
    end
  end

  def current_seed(%__MODULE__{} = state) do
    case current_iteration(state) do
      nil -> state.initial_seed
      iteration -> iteration.seed
    end
  end

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
