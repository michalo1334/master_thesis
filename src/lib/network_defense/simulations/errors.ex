defmodule NetworkDefense.Simulations.Errors do
  @moduledoc false

  alias NetworkDefense.Graph.Errors, as: GraphErrors

  @codes [:invalid_initial_foothold, :persistence_failed, :task_unavailable, :internal_error]

  @type code :: :invalid_initial_foothold | :persistence_failed | :task_unavailable | :internal_error
  @type error :: GraphErrors.code() | code()

  @spec codes() :: [code()]
  def codes, do: @codes
end
