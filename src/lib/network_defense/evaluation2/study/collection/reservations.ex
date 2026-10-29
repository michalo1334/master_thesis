defmodule NetworkDefense.Evaluation2.Study.Collection.Reservations do
  @moduledoc false

  # Retry-safe effect reservation of one collection item.
  #
  # The reservation service loads the item, loads the plan of its phase run, and
  # derives the domain request from the stored work request. The simulation
  # reservation also loads the completed optimization that the item links.
  #
  # The row lock and the create-or-reuse transaction make a retry return the
  # linked record instead of creating a second one.

  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Simulation.Experiment

  # Reserve or reuse the optimization run of one collection item.
  @spec reserve_optimization(Ecto.UUID.t()) ::
          {:ok, OptimizationRun.t()} | {:error, Error.t()}
  def reserve_optimization(_item_id),
    do: {:error, Placeholder.error(:reserve_optimization)}

  # Reserve or reuse the simulation experiment of one collection item.
  #
  # The item already links a completed optimization run.
  @spec reserve_experiment(Ecto.UUID.t()) :: {:ok, Experiment.t()} | {:error, Error.t()}
  def reserve_experiment(_item_id),
    do: {:error, Placeholder.error(:reserve_experiment)}
end
