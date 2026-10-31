defmodule NetworkDefense.Evaluation2.Study.Workflow do
  @moduledoc """
  Caller-owned study progression with canonical Gust completion proofs.

  Persistence owns lifecycle transitions. Gust owns scheduling. RunMonitor only
  waits. Run provisioning retains create-link-dispatch order and locks the
  authoritative Gust row before conditional dispatch.
  """

  import Ecto.Query
  require Logger

  alias Gust.DAG.{Run.Trigger, Terminator}
  alias Gust.Flows
  alias Gust.Flows.{Run, Task}
  alias Gust.Repo, as: GustRepo
  alias NetworkDefense.Evaluation2.Study.{Error, Final, Persistence, Pilot, Tier, Views}

  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Boundary,
    as: TierBoundary

  alias NetworkDefense.Evaluation2.Study.Persistence.{Executions, PhaseRun}
  alias NetworkDefense.Evaluation2.Study.Workflow.RunMonitor

  @boundary_states [:awaiting_final, :succeeded, :failed, :cancelled]

  @spec continue(Ecto.UUID.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def continue(execution_id, opts \\ []) do
    case Keyword.get(opts, :timeout, :infinity) do
      :infinity ->
        progress(execution_id, :infinity)

      timeout when is_integer(timeout) and timeout >= 0 ->
        progress(execution_id, System.monotonic_time(:millisecond) + timeout)

      _invalid ->
        failure = error("invalid_timeout", "Supply a non-negative timeout.")
        {:error, %{failure | category: :validation_failed}}
    end
  end

  defp progress(execution_id, deadline) do
    with {:ok, context} <- public(Executions.fetch_context(execution_id)) do
      cond do
        context.execution.state in @boundary_states ->
          status(context)

        remaining(deadline) == 0 ->
          status(context)

        context.execution.state in [:collecting_pilot, :analyzing_pilot] ->
          progress_pilot(context, deadline)

        context.execution.state == :collecting_final ->
          progress_final(context, deadline)

        true ->
          {:error, error("final_analysis_not_implemented", "Final analysis belongs to Goal 05.")}
      end
    end
  end

  defp progress_pilot(context, deadline) do
    case ensure_phase_run(context.active_phase.id, context.active_phase.phase) do
      {:ok, phase_run} -> await_settle(context, phase_run, deadline)
      {:error, failure} -> recover_progress(context, deadline, failure)
    end
  end

  defp progress_final(context, deadline) do
    case next_final(context) do
      {:ok, {:complete, tier_runs}} ->
        prepare_final_snapshot(context, tier_runs, deadline)

      {:ok, {:pending, phase_run}} ->
        await_settle(context, phase_run, deadline)

      {:error, failure} ->
        recover_progress(context, deadline, failure)
    end
  end

  defp await_settle(context, phase_run, deadline) do
    with {:ok, waiting} <- wait(phase_run, context.execution.id, remaining(deadline)) do
      finish_wait(waiting, context, phase_run, deadline)
    end
  end

  defp finish_wait(waiting, context, _phase_run, _deadline)
       when waiting in [:timeout, :cancelled],
       do: reload_status(context.execution.id)

  defp finish_wait(:terminal, context, phase_run, deadline),
    do: settle(context, phase_run, deadline)

  defp prepare_final_snapshot(context, tier_runs, deadline) do
    case Final.Collection.prepare_snapshot(tier_runs, context.execution) do
      {:ok, _snapshot, _timing} ->
        case public(Executions.accept_final_collection(context.active_phase.id)) do
          {:ok, _accepted} -> progress(context.execution.id, deadline)
          {:error, failure} -> terminal_or_error(context.execution.id, failure)
        end

      {:error, failure} ->
        settle_failure(context.active_phase.id, context.execution.id, failure)
    end
  end

  defp next_final(context), do: final_prefix(context, Tier.all(), [])

  defp final_prefix(_context, [], completed), do: {:ok, {:complete, Enum.reverse(completed)}}

  defp final_prefix(context, [tier | rest], completed) do
    case Persistence.fetch_phase_run(context.active_phase.id, tier) do
      {:ok, phase_run} ->
        inspect_final_run(context, phase_run, rest, completed)

      {:error, %Persistence.Error{kind: :not_found}} ->
        pending_final(context.active_phase.id, tier)

      failure ->
        public(failure)
    end
  end

  defp pending_final(phase_id, tier) do
    with {:ok, run} <- ensure_phase_run(phase_id, :final_collection, tier),
         do: {:ok, {:pending, run}}
  end

  defp inspect_final_run(context, phase_run, rest, completed) do
    with {:ok, run} <- fetch_run(phase_run.gust_run_id),
         do: inspect_final_status(run, context, phase_run, rest, completed)
  end

  defp inspect_final_status(%Run{status: :succeeded} = run, context, phase_run, rest, completed) do
    with {:ok, output} <- final_tier_result(phase_run.id) do
      Final.Timing.release(output.clock_session)
      tier_run = Final.TierRun.from_output(run.id, output)
      final_prefix(context, rest, [tier_run | completed])
    end
  end

  defp inspect_final_status(_run, _context, phase_run, _rest, _completed) do
    with {:ok, canonical} <- dispatch_linked(phase_run), do: {:ok, {:pending, canonical}}
  end

  defp recover_progress(previous, deadline, failure) do
    case public(Executions.fetch_context(previous.execution.id)) do
      {:ok, current} when current.execution.state != previous.execution.state ->
        progress(current.execution.id, deadline)

      _unchanged_or_unavailable ->
        terminal_or_error(previous.execution.id, failure)
    end
  end

  defp wait(phase_run, execution_id, timeout) do
    case RunMonitor.await(phase_run.gust_run_id, execution_id, timeout) do
      :timeout -> {:ok, :timeout}
      result -> result
    end
  end

  defp settle(context, phase_run, deadline) do
    case fetch_run(phase_run.gust_run_id) do
      {:ok, %Run{status: :failed}} ->
        failure = run_failure(context.active_phase.phase)
        settle_failure(context.active_phase.id, context.execution.id, failure)

      {:ok, %Run{status: :succeeded}} ->
        if context.active_phase.phase == :final_collection,
          do: progress(context.execution.id, deadline),
          else: accept_completed(context.active_phase, phase_run, context.execution.id, deadline)

      {:ok, _run} ->
        {:error, incomplete()}

      failure ->
        failure
    end
  end

  defp run_failure(:final_collection), do: error("final_run_failed", "The Final tier run failed.")
  defp run_failure(_pilot), do: error("pilot_run_failed", "The Pilot run failed.")

  defp accept_completed(phase, phase_run, execution_id, deadline) do
    result =
      case phase.phase do
        :pilot_collection ->
          with {:ok, _receipt} <- pilot_collection_result(phase_run.id) do
            public(Executions.accept_pilot_collection(phase.id))
          end

        :pilot_analysis ->
          with {:ok, output} <- pilot_analysis_result(phase_run.id) do
            public(Executions.accept_pilot_analysis(phase.id, output.outcome))
          end
      end

    case result do
      {:ok, _context} -> progress(execution_id, deadline)
      {:error, failure} -> terminal_or_error(execution_id, failure)
    end
  end

  defp settle_failure(phase_id, execution_id, failure) do
    case public(Executions.fail_phase(phase_id, failure)) do
      {:ok, context} -> status(context)
      {:error, error} -> terminal_or_error(execution_id, error)
    end
  end

  defp terminal_or_error(execution_id, failure) do
    case public(Executions.fetch_context(execution_id)) do
      {:ok, %{execution: %{state: state}} = context} when state in @boundary_states ->
        status(context)

      _active_or_unavailable ->
        {:error, failure}
    end
  end

  defp reload_status(execution_id) do
    with {:ok, context} <- public(Executions.fetch_context(execution_id)), do: status(context)
  end

  defp status(context), do: {:ok, Views.status(context.revision, context.execution)}
  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  @spec ensure_next_run(Ecto.UUID.t()) :: {:ok, PhaseRun.t() | nil} | {:error, Error.t()}
  def ensure_next_run(execution_id) do
    with {:ok, context} <- public(Executions.fetch_context(execution_id)),
         do: ensure_active_run(context)
  end

  defp ensure_active_run(%{active_phase: nil}), do: {:ok, nil}

  defp ensure_active_run(%{active_phase: %{phase: kind, id: id}})
       when kind in [:pilot_collection, :pilot_analysis],
       do: ensure_phase_run(id, kind)

  defp ensure_active_run(%{active_phase: %{phase: :final_collection}} = context) do
    case next_final(context) do
      {:ok, {:pending, phase_run}} -> {:ok, phase_run}
      {:ok, {:complete, _tier_runs}} -> {:ok, nil}
      failure -> failure
    end
  end

  defp ensure_active_run(_final_analysis),
    do: {:error, error("final_analysis_not_implemented", "Final analysis belongs to Goal 05.")}

  @spec ensure_pilot_collection_run(Ecto.UUID.t()) :: {:ok, PhaseRun.t()} | {:error, Error.t()}
  def ensure_pilot_collection_run(phase_id), do: ensure_phase_run(phase_id, :pilot_collection)

  @spec ensure_pilot_analysis_run(Ecto.UUID.t()) :: {:ok, PhaseRun.t()} | {:error, Error.t()}
  def ensure_pilot_analysis_run(phase_id), do: ensure_phase_run(phase_id, :pilot_analysis)

  defp ensure_phase_run(phase_id, kind, run_key \\ :single) do
    with {:ok, context} <- public(Persistence.fetch_phase_context(phase_id)),
         :ok <- active_phase(context, kind) do
      case Persistence.fetch_phase_run(phase_id, run_key) do
        {:ok, phase_run} -> dispatch_linked(phase_run)
        {:error, %Persistence.Error{kind: :not_found}} -> create_linked(context, kind, run_key)
        failure -> public(failure)
      end
    end
  end

  defp active_phase(
         %{phase: %{phase: :pilot_collection}, execution: %{state: :collecting_pilot}},
         :pilot_collection
       ),
       do: :ok

  defp active_phase(
         %{phase: %{phase: :pilot_analysis}, execution: %{state: :analyzing_pilot}},
         :pilot_analysis
       ),
       do: :ok

  defp active_phase(
         %{phase: %{phase: :final_collection}, execution: %{state: :collecting_final}},
         :final_collection
       ),
       do: :ok

  defp active_phase(_context, _kind),
    do: {:error, error("phase_not_active", "The study phase is not active.")}

  defp create_linked(context, kind, run_key) do
    phase_run_id = Ecto.UUID.generate()

    with {:ok, params} <- run_params(context, kind, phase_run_id),
         {:ok, dag_id} <- dag_id(kind),
         {:ok, run} <- create_run(dag_id, params) do
      link_created(context.phase.id, run_key, phase_run_id, run)
    end
  end

  defp link_created(phase_id, run_key, phase_run_id, run) do
    case public(Persistence.link_phase_run(phase_id, run_key, phase_run_id, run.id)) do
      {:ok, canonical} ->
        if canonical.gust_run_id != run.id, do: discard_created(run)
        dispatch_linked(canonical)

      {:error, _failure} = failure ->
        discard_created(run)
        failure
    end
  end

  defp run_params(_context, :pilot_collection, phase_run_id) do
    {:ok,
     Pilot.CollectionContract.to_params(%Pilot.CollectionContract.Input{
       phase_run_id: phase_run_id
     })}
  end

  defp run_params(context, :pilot_analysis, phase_run_id) do
    with {:ok, snapshot} <- pilot_snapshot(context.execution.id) do
      {:ok,
       Pilot.AnalysisContract.to_params(%Pilot.AnalysisContract.Input{
         phase_run_id: phase_run_id,
         snapshot_id: snapshot.id
       })}
    end
  end

  defp run_params(_context, :final_collection, phase_run_id) do
    {:ok, Final.TierContract.to_params(%Final.TierContract.Input{phase_run_id: phase_run_id})}
  end

  @spec pilot_snapshot(Ecto.UUID.t()) ::
          {:ok, Persistence.EvidenceSnapshot.t()} | {:error, Error.t()}
  def pilot_snapshot(execution_id) do
    with {:ok, phase} <-
           public(Persistence.fetch_execution_phase(execution_id, :pilot_collection)) do
      public(Persistence.fetch_phase_evidence_snapshot(phase.id))
    end
  end

  defp dag_name(:final_collection), do: "evaluation2_study_final_tier_collection"
  defp dag_name(:pilot_collection), do: "evaluation2_study_pilot_collection"
  defp dag_name(:pilot_analysis), do: "evaluation2_study_pilot_analysis"
  defp terminal_name(:final_collection), do: "complete_final_tier_collection"
  defp terminal_name(:pilot_collection), do: "complete_pilot_collection"
  defp terminal_name(:pilot_analysis), do: "select_pilot_outcome"

  defp dag_id(kind) do
    case contained(fn -> Flows.get_dag_by_name(dag_name(kind)) end) do
      %Flows.Dag{id: id} -> {:ok, id}
      {:error, _} = failure -> failure
      nil -> {:error, unavailable()}
    end
  end

  defp create_run(dag_id, params) do
    case contained(fn -> Flows.create_run(%{dag_id: dag_id, params: params}) end) do
      {:ok, %Run{} = run} -> {:ok, run}
      _error -> {:error, unavailable()}
    end
  end

  defp discard_created(%Run{id: id}) do
    contained(fn ->
      GustRepo.delete_all(from run in Run, where: run.id == ^id and run.status == :created)
    end)

    :ok
  end

  defp dispatch_linked(phase_run) do
    result =
      contained(fn -> GustRepo.transaction(fn -> locked_dispatch(phase_run.gust_run_id) end) end)

    case result do
      {:ok, %Run{status: :created}} -> {:error, unavailable()}
      {:ok, %Run{}} -> {:ok, phase_run}
      _failure -> {:error, unavailable()}
    end
  end

  defp locked_dispatch(run_id) do
    case GustRepo.one(from run in Run, where: run.id == ^run_id, lock: "FOR UPDATE") do
      nil -> GustRepo.rollback(:missing_run)
      %Run{status: :created} = run -> Trigger.dispatch_run(run)
      %Run{} = run -> run
    end
  end

  @spec pilot_collection_result(Ecto.UUID.t()) ::
          {:ok, Pilot.CollectionContract.Output.t()} | {:error, Error.t()}
  def pilot_collection_result(phase_run_id), do: completed(phase_run_id, :pilot_collection)

  @spec pilot_analysis_result(Ecto.UUID.t()) ::
          {:ok, Pilot.AnalysisContract.Output.t()} | {:error, Error.t()}
  def pilot_analysis_result(phase_run_id), do: completed(phase_run_id, :pilot_analysis)

  @spec final_tier_result(Ecto.UUID.t()) ::
          {:ok, Final.TierContract.Output.t()} | {:error, Error.t()}
  def final_tier_result(phase_run_id), do: completed(phase_run_id, :final_collection)

  @doc "Rebuild completed Final durations from canonical Gust receipts."
  def final_timing(execution_id) do
    with {:ok, phase} <-
           public(Persistence.fetch_execution_phase(execution_id, :final_collection)),
         {:ok, context} <- public(Persistence.fetch_phase_context(phase.id)),
         {:ok, runs} <- completed_final_runs(context, Tier.all(), []) do
      {:ok, Final.Timing.summarize(runs)}
    end
  end

  defp completed_final_runs(_context, [], runs), do: {:ok, Enum.reverse(runs)}

  defp completed_final_runs(context, [tier | rest], runs) do
    with {:ok, canonical} <- public(Persistence.fetch_phase_run(context.phase.id, tier)),
         {:ok, output} <- final_tier_result(canonical.id) do
      completed_final_runs(context, rest, [
        Final.TierRun.from_output(canonical.gust_run_id, output) | runs
      ])
    end
  end

  defp completed(phase_run_id, kind) do
    with {:ok, context} <- public(Persistence.fetch_phase_run_context(phase_run_id)),
         :ok <- phase_kind(context, kind),
         {:ok, canonical} <-
           public(Persistence.fetch_phase_run(context.phase.id, context.phase_run.run_key)),
         true <- canonical.id == phase_run_id,
         {:ok, run} <- fetch_run(canonical.gust_run_id),
         true <- run.status == :succeeded,
         {:ok, expected} <- run_params(context, kind, canonical.id),
         true <- run.params == expected,
         {:ok, terminal} <- terminal(run.id, kind),
         {:ok, output} <- decode_output(kind, terminal.result),
         :ok <- validate_output(context, kind, output) do
      {:ok, output}
    else
      {:error, %Error{}} = failure -> failure
      _invalid -> {:error, incomplete()}
    end
  end

  defp phase_kind(
         %{phase: %{phase: :final_collection}, phase_run: %{run_key: tier}},
         :final_collection
       )
       when tier in [:small, :medium, :large], do: :ok

  defp phase_kind(%{phase: %{phase: kind}, phase_run: %{run_key: :single}}, kind)
       when kind in [:pilot_collection, :pilot_analysis], do: :ok

  defp phase_kind(_context, _kind), do: {:error, incomplete()}

  defp terminal(run_id, kind) do
    case contained(fn -> Flows.get_tasks_by_name(terminal_name(kind), run_id) end) do
      [%Task{status: :succeeded} = task] -> {:ok, task}
      _invalid -> {:error, incomplete()}
    end
  end

  defp decode_output(:final_collection, raw), do: Final.TierContract.decode_output(raw)
  defp decode_output(:pilot_collection, raw), do: Pilot.CollectionContract.decode_output(raw)
  defp decode_output(:pilot_analysis, raw), do: Pilot.AnalysisContract.decode_output(raw)

  defp validate_output(context, :final_collection, output) do
    with true <- output.phase_run_id == context.phase_run.id,
         true <- output.tier == context.phase_run.run_key,
         {:ok, prepared} <- TierBoundary.prepared(context.phase_run.gust_run_id),
         true <- prepared.phase_run_id == output.phase_run_id and prepared.tier == output.tier,
         true <- prepared.clock_session == output.clock_session,
         :ok <- validate_replica_receipts(context.phase_run.gust_run_id, output) do
      :ok
    else
      _invalid -> {:error, incomplete()}
    end
  end

  defp validate_output(_context, :pilot_collection, _output), do: :ok

  defp validate_output(context, :pilot_analysis, output),
    do: Pilot.Analysis.validate_output(context.revision.definition, output)

  defp validate_replica_receipts(run_id, output) do
    Enum.reduce_while(0..4, :ok, fn position, :ok ->
      with {:ok, receipt} <- TierBoundary.stored_receipt(run_id, position),
           {:ok, {^position, timing}} <- TierBoundary.decode_replica(receipt),
           true <- timing == Map.fetch!(output.timing.replicas, position) do
        {:cont, :ok}
      else
        _invalid -> {:halt, {:error, incomplete()}}
      end
    end)
  end

  defp fetch_run(run_id) do
    case contained(fn -> GustRepo.get(Run, run_id) end) do
      %Run{} = run -> {:ok, run}
      _missing -> {:error, incomplete()}
    end
  end

  @doc "Best-effort Gust stopping after durable application cancellation."
  @spec stop(Ecto.UUID.t()) :: :ok
  def stop(execution_id) do
    for kind <- [:pilot_collection, :pilot_analysis, :final_collection] do
      stop_phase(execution_id, kind)
    end

    :ok
  end

  defp stop_phase(execution_id, kind) do
    with {:ok, phase} <- Persistence.fetch_execution_phase(execution_id, kind),
         {:ok, phase_runs} <- Persistence.list_phase_runs(phase.id) do
      Enum.each(phase_runs, &stop_run/1)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  defp stop_run(phase_run) do
    with {:ok, %Run{status: status} = run} when status not in [:succeeded, :failed] <-
           stopped_pending_run(phase_run.gust_run_id) do
      Terminator.stop_run(run)
    end
  end

  # An enqueued run has no active runner for Gust's stop gateway. Fence it under
  # the authoritative row lock before it can be claimed.
  defp stopped_pending_run(run_id) do
    contained(fn -> GustRepo.transaction(fn -> stop_pending(run_id) end) end)
  end

  defp stop_pending(run_id) do
    case GustRepo.one(from run in Run, where: run.id == ^run_id, lock: "FOR UPDATE") do
      %Run{status: status} = run when status in [:created, :enqueued] -> fail_pending(run)
      run -> run
    end
  end

  defp fail_pending(run) do
    case Flows.update_run_status(run, :failed) do
      {:ok, updated} -> updated
      {:error, reason} -> GustRepo.rollback(reason)
    end
  end

  defp public({:error, %Persistence.Error{} = failure}), do: {:error, Views.error(failure)}
  defp public(result), do: result

  defp contained(fun) do
    fun.()
  rescue
    exception in [Postgrex.Error, DBConnection.ConnectionError, DBConnection.OwnershipError] ->
      Logger.error("Evaluation2 Gust storage failed", error: Exception.message(exception))
      {:error, unavailable()}
  end

  defp unavailable, do: error("collection_unavailable", "The study run is unavailable.")

  defp incomplete,
    do: error("collection_incomplete", "The study run has no valid completion proof.")

  defp error(code, message),
    do: %Error{
      category: :unavailable,
      issues: [%Error.Issue{code: code, path: [], message: message}]
    }
end
