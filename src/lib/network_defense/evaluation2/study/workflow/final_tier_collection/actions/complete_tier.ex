defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.CompleteTier do
  @moduledoc false

  # Fan-in terminal task of one Final tier collection run.
  #
  # It re-reads the measured environment label, gathers the five completed
  # replica receipts of the run, and stores the encoded tier output. The Gust
  # success of this task is the tier completion fact, because the measured
  # durations travel in the stored task results.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Final.TierContract
  alias NetworkDefense.Evaluation2.Study.Result.Timing.Tier, as: TierTiming
  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Boundary
  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Prepared

  @failure "Evaluation2 Final tier collection completion failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, {context, prepared}} <-
           Boundary.prepared_run(Keyword.fetch!(args, :params), action_context),
         :ok <-
           Boundary.logged_status(
             @failure,
             Boundary.expect_environment(context.revision.definition)
           ),
         {:ok, receipts} <- receipts(action_context.run_id),
         {:ok, timing} <- timing(receipts),
         {:ok, params} <- encode(prepared, timing) do
      params
    else
      {:error, cause} -> fail(cause)
    end
  end

  @doc """
  Build the tier timing value from the raw stored replica receipts.

  Five distinct measured positions are required, so an incomplete or repeated
  receipt never becomes a timing value.
  """
  @spec replica_timing([term()]) :: {:ok, TierTiming.t()} | {:error, :incomplete_timing}
  def replica_timing(receipts) do
    positions = Enum.to_list(Boundary.measured_positions())

    with true <- length(receipts) == length(positions),
         {:ok, replicas} <- replica_map(receipts),
         true <- Enum.sort(Map.keys(replicas)) == positions do
      {:ok, %TierTiming{replicas: replicas}}
    else
      _incomplete -> {:error, :incomplete_timing}
    end
  end

  @spec receipts(pos_integer()) :: {:ok, [term()]} | {:error, term()}
  defp receipts(run_id) do
    Boundary.measured_positions()
    |> Enum.reduce_while({:ok, []}, fn position, {:ok, stored} ->
      case Boundary.stored_receipt(run_id, position) do
        {:ok, receipt} -> {:cont, {:ok, [receipt | stored]}}
        {:error, _cause} = failure -> {:halt, failure}
      end
    end)
    |> stored_receipts()
  end

  @spec timing([term()]) :: {:ok, TierTiming.t()} | {:error, term()}
  defp timing(receipts) do
    Boundary.logged(@failure, replica_timing(receipts))
  end

  @spec encode(Prepared.t(), TierTiming.t()) :: {:ok, map()} | {:error, term()}
  defp encode(prepared, timing) do
    output = %TierContract.Output{
      phase_run_id: prepared.phase_run_id,
      tier: prepared.tier,
      clock_session: prepared.clock_session,
      timing: timing
    }

    case TierContract.encode_output(output) do
      {:ok, params} -> {:ok, params}
      :error -> Boundary.tagged(:invalid_output, @failure)
    end
  end

  @spec replica_map([term()]) :: {:ok, map()} | :error
  defp replica_map(receipts) do
    Enum.reduce_while(receipts, {:ok, %{}}, fn receipt, {:ok, replicas} ->
      case Boundary.decode_replica(receipt) do
        {:ok, {position, replica}} when not is_map_key(replicas, position) ->
          {:cont, {:ok, Map.put(replicas, position, replica)}}

        _invalid ->
          {:halt, :error}
      end
    end)
  end

  @spec stored_receipts({:ok, [term()]} | {:error, term()}) ::
          {:ok, [term()]} | {:error, term()}
  defp stored_receipts({:ok, receipts}), do: {:ok, Enum.reverse(receipts)}
  defp stored_receipts({:error, _cause} = failure), do: failure

  # A tagged timing or environment failure is permanent, so Gust must not retry
  # the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
