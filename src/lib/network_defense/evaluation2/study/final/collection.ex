defmodule NetworkDefense.Evaluation2.Study.Final.Collection do
  @moduledoc """
  Validates measured replicas and prepares Final evidence.

  Workflow proves canonical completion and exact stored timing receipts before
  calling this capability. This capability checks their physical sources and
  scientific equality before preparing a snapshot.
  Persistence.Executions separately owns lifecycle acceptance.
  """

  alias NetworkDefense.Evaluation2.Study.{Collection, Error, Persistence, Tier, Views}
  alias NetworkDefense.Evaluation2.Study.Final.{TierContract, TierRun, Timing}

  def prepare_snapshot(tier_runs, execution) do
    with {:ok, phase} <-
           stored(Persistence.fetch_execution_phase(execution.id, :final_collection)),
         {:ok, context} <- stored(Persistence.fetch_phase_context(phase.id)),
         :ok <- validate_tiers(tier_runs),
         {:ok, observations} <- validate_replicas(tier_runs, context),
         {:ok, evidence} <-
           Collection.project_evidence(
             observations,
             context.revision.definition,
             context.execution.selection.plan_count_per_side
           ),
         {:ok, snapshot} <- stored(Persistence.insert_evidence_snapshot(phase.id, evidence)) do
      {:ok, snapshot, Timing.summarize(tier_runs)}
    end
  end

  defp validate_tiers(tier_runs) do
    if Enum.map(tier_runs, & &1.tier) == Tier.all(),
      do: :ok,
      else: failure("incomplete_final_tiers")
  end

  defp validate_replicas(tier_runs, context) do
    Enum.reduce_while(tier_runs, {:ok, []}, fn tier_run, {:ok, collected} ->
      case validate_tier(tier_run, context) do
        {:ok, observations} -> {:cont, {:ok, collected ++ observations}}
        failure -> {:halt, failure}
      end
    end)
  end

  defp validate_tier(%TierRun{} = run, context) do
    with {:ok, canonical} <- stored(Persistence.fetch_phase_run(context.phase.id, run.tier)),
         true <- canonical.id == run.phase_run_id and canonical.gust_run_id == run.gust_run_id,
         :ok <- validate_timing(run),
         {:ok, _plan} <-
           Collection.prepare_final(
             run.phase_run_id,
             context.revision.definition,
             context.execution.selection,
             run.tier
           ),
         {:ok, _warm_up} <- Collection.replica_observations(run.phase_run_id, -1),
         {:ok, representative} <- Collection.replica_observations(run.phase_run_id, 0),
         :ok <- equal_replicas(run.phase_run_id, representative) do
      {:ok, representative}
    else
      {:error, _} = failure -> failure
      _invalid -> failure("invalid_final_tier_binding")
    end
  end

  defp validate_timing(run) do
    encoded =
      TierContract.encode_output(%TierContract.Output{
        phase_run_id: run.phase_run_id,
        tier: run.tier,
        clock_session: run.clock_session,
        timing: run.timing
      })

    with {:ok, params} <- encoded,
         {:ok, _output} <- TierContract.decode_output(params) do
      :ok
    else
      :error -> failure("incomplete_final_timing")
    end
  end

  defp equal_replicas(phase_run_id, representative) do
    Enum.reduce_while(1..4, :ok, fn position, :ok ->
      case Collection.replica_observations(phase_run_id, position) do
        {:ok, ^representative} -> {:cont, :ok}
        {:ok, _unequal} -> {:halt, failure("unequal_final_replicas")}
        failure -> {:halt, failure}
      end
    end)
  end

  defp stored({:error, %Persistence.Error{} = error}), do: {:error, Views.error(error)}
  defp stored(result), do: result

  defp failure(code) do
    {:error,
     %Error{
       category: :unavailable,
       issues: [
         %Error.Issue{
           code: code,
           path: [],
           message: "Final collection proof is incomplete or inconsistent."
         }
       ]
     }}
  end
end
