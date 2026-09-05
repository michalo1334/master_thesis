defmodule NetworkDefense.Compute.ScatterGather do
  @moduledoc false

  @otp_app :network_defense

  @spec run(module(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def run(operation, input, opts) do
    executor =
      @otp_app
      |> Application.fetch_env!(__MODULE__)
      |> Keyword.fetch!(:executor)

    executor.run(operation, input, opts)
  end

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
