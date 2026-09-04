defmodule NetworkDefense.Compute.ScatterGather do
  @moduledoc false

  @type partition_key :: term()
  @type partition :: term()
  @type work_units :: pos_integer()
  @type partition_result :: term()
  @type reason :: term()
  @type stats :: %{compute_duration_ms: non_neg_integer()}

  @callback scatter(input :: term()) ::
              Enumerable.t({partition_key(), work_units(), partition()})

  @callback execute(fetch_partition :: (-> partition())) ::
              {:ok, partition_result()} | {:error, reason()}

  @callback gather(
              results :: [{partition_key(), partition_result()}],
              input :: term(),
              stats()
            ) :: {:ok, term()} | {:error, reason()}
end
