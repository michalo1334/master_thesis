defmodule NetworkDefense.Evaluation2.Study.Collection.Execute do
  @moduledoc false

  # Execution of the two collection effects of one item.
  #
  # Each operation reserves or reuses its linked domain record, runs it, and waits
  # for completion. The split matches the two mapped Gust stages and keeps the two
  # Final timing boundaries separate.
  #
  # Success returns `:ok` because the collection item already owns the effect
  # links.

  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error

  @spec run_optimization(Ecto.UUID.t()) :: :ok | {:error, Error.t()}
  def run_optimization(_item_id),
    do: {:error, Placeholder.error(:run_optimization)}

  # Run the simulation effect of one collection item.
  #
  # The item links the completed optimization run that the simulation consumes.
  @spec run_simulation(Ecto.UUID.t()) :: :ok | {:error, Error.t()}
  def run_simulation(_item_id), do: {:error, Placeholder.error(:run_simulation)}
end
