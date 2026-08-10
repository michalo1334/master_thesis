defmodule NetworkDefense.Optimizations.Errors do
  @moduledoc false

  alias NetworkDefense.Graph.Errors, as: GraphErrors
  alias NetworkDefense.Simulations.Errors, as: SimulationErrors

  @codes [
    :unknown_strategy,
    :reachability_required,
    :persistence_failed,
    :task_unavailable,
    :internal_error
  ]

  @type code ::
          :unknown_strategy
          | :reachability_required
          | :persistence_failed
          | :task_unavailable
          | :internal_error

  @type error :: GraphErrors.code() | SimulationErrors.code() | code()

  @spec codes() :: [code()]
  def codes, do: @codes
end
