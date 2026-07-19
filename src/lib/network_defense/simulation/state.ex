defmodule NetworkDefense.Simulation.State do
  @moduledoc """
  Represents simulation step
  """
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Rules.Rule
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph

  @type t :: %__MODULE__{
          graph: %Graph{},
          initial_seed: term(),
          initial_attacker_state: AttackerState.t(),
          rules: list(Rule.t()),
          iteration_count: non_neg_integer(),
          iterations: list(IterationStep.t())
        }

  defstruct [
    :graph,
    :initial_seed,
    :initial_attacker_state,
    :rules,
    :iteration_count,
    :iterations
  ]

  def new(opts \\ []) do
    defaults = [
      initial_seed: 0,
      iteration_count: 1000,
      iterations: []
    ]

    struct!(__MODULE__, Keyword.merge(defaults, opts))
  end

  def current_iteration(%__MODULE__{iterations: iterations}) do
    case iterations do
      [] -> nil
      _ -> hd(iterations)
    end
  end

  def current_attacker_state(%__MODULE__{} = state) do
    case state.iterations do
      [] -> state.initial_attacker_state
      _ -> current_iteration(state).attacker_state
    end
  end

  def current_seed(%__MODULE__{} = state) do
    case state.iterations do
      [] -> state.initial_seed
      _ -> current_iteration(state).seed
    end
  end

  def add_iteration_step(%__MODULE__{} = state, iteration_step) do
    %__MODULE__{state | iterations: [iteration_step | state.iterations]}
  end
end
