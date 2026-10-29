defmodule NetworkDefense.Evaluation2.Study.Collection.Items do
  @moduledoc false

  # Collection items of one replica.
  #
  # A plan fixes the complete ordered request list, and a replica adds one
  # coordinate per planned request. `prepare_replica/2` creates one row for every
  # plan item and uses the plan index as item position, so a replica is always
  # complete. A repeated call returns the same ordered rows.
  #
  # Individual row creation stays private.

  alias NetworkDefense.Evaluation2.CollectionItem
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error

  # Create or load the complete ordered item batch of one replica.
  #
  # Pilot uses measured replica 0. Final uses warm-up -1 and measured replicas
  # 0..4.
  @spec prepare_replica(Ecto.UUID.t(), CollectionItem.replica_position()) ::
          {:ok, [CollectionItem.t()]} | {:error, Error.t()}
  def prepare_replica(_plan_id, _replica_position),
    do: {:error, Placeholder.error(:prepare_replica)}

  @spec fetch!(Ecto.UUID.t()) :: CollectionItem.t()
  def fetch!(_item_id), do: raise(NotImplementedError, function: :fetch!)

  # List the items of one replica in item order.
  @spec list_replica(Ecto.UUID.t(), CollectionItem.replica_position()) ::
          [CollectionItem.t()]
  def list_replica(_phase_run_id, _replica_position),
    do: raise(NotImplementedError, function: :list_replica)
end
