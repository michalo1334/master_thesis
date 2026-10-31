defmodule NetworkDefense.Evaluation2.Study.Workflow do
  @moduledoc """
  Caller-owned Pilot progression with canonical Gust completion proofs.

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
  alias NetworkDefense.Evaluation2.Study.{Error, Persistence, Pilot, Views}
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

        true ->
          {:error, error("final_not_implemented", "Final execution is the next milestone.")}
      end
    end
  end

  defp progress_pilot(context, deadline) do
    with {:ok, phase_run} <- ensure_phase_run(context.active_phase.id, context.active_phase.phase),
         {:ok, waiting} <- wait(phase_run, context.execution.id, remaining(deadline)) do
      case waiting do
        :timeout -> reload_status(context.execution.id)
        :cancelled -> reload_status(context.execution.id)
        :terminal -> settle(context, phase_run, deadline)
      end
    else
      {:error, failure} -> recover_progress(context, deadline, failure)
    end
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
        failure = error("pilot_run_failed", "The Pilot run failed.")
        settle_failure(context.active_phase.id, context.execution.id, failure)

      {:ok, %Run{status: :succeeded}} ->
        accept_completed(context.active_phase, phase_run, context.execution.id, deadline)

      {:ok, _run} ->
        {:error, incomplete()}

      failure ->
        failure
    end
  end

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
    with {:ok, context} <- public(Executions.fetch_context(execution_id)) do
      case context.active_phase do
        nil ->
          {:ok, nil}

        %{phase: kind, id: id} when kind in [:pilot_collection, :pilot_analysis] ->
          ensure_phase_run(id, kind)

        _final ->
          {:error, error("final_not_implemented", "Final execution is the next milestone.")}
      end
    end
  end

  @spec ensure_pilot_collection_run(Ecto.UUID.t()) :: {:ok, PhaseRun.t()} | {:error, Error.t()}
  def ensure_pilot_collection_run(phase_id), do: ensure_phase_run(phase_id, :pilot_collection)

  @spec ensure_pilot_analysis_run(Ecto.UUID.t()) :: {:ok, PhaseRun.t()} | {:error, Error.t()}
  def ensure_pilot_analysis_run(phase_id), do: ensure_phase_run(phase_id, :pilot_analysis)

  defp ensure_phase_run(phase_id, kind) do
    with {:ok, context} <- public(Persistence.fetch_phase_context(phase_id)),
         :ok <- active_phase(context, kind) do
      case Persistence.fetch_phase_run(phase_id, :single) do
        {:ok, phase_run} -> dispatch_linked(phase_run)
        {:error, %Persistence.Error{kind: :not_found}} -> create_linked(context, kind)
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

  defp active_phase(_context, _kind),
    do: {:error, error("phase_not_active", "The Pilot phase is not active.")}

  defp create_linked(context, kind) do
    phase_run_id = Ecto.UUID.generate()

    with {:ok, params} <- run_params(context, kind, phase_run_id),
         {:ok, dag_id} <- dag_id(kind),
         {:ok, run} <- create_run(dag_id, params) do
      link_created(context.phase.id, phase_run_id, run)
    end
  end

  defp link_created(phase_id, phase_run_id, run) do
    case public(Persistence.link_phase_run(phase_id, :single, phase_run_id, run.id)) do
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

  @spec pilot_snapshot(Ecto.UUID.t()) ::
          {:ok, Persistence.EvidenceSnapshot.t()} | {:error, Error.t()}
  def pilot_snapshot(execution_id) do
    with {:ok, phase} <-
           public(Persistence.fetch_execution_phase(execution_id, :pilot_collection)) do
      public(Persistence.fetch_phase_evidence_snapshot(phase.id))
    end
  end

  defp dag_name(:pilot_collection), do: "evaluation2_study_pilot_collection"
  defp dag_name(:pilot_analysis), do: "evaluation2_study_pilot_analysis"
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

  defp completed(phase_run_id, kind) do
    with {:ok, context} <- public(Persistence.fetch_phase_run_context(phase_run_id)),
         :ok <- phase_kind(context, kind),
         {:ok, canonical} <- public(Persistence.fetch_phase_run(context.phase.id, :single)),
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

  defp phase_kind(%{phase: %{phase: kind}, phase_run: %{run_key: :single}}, kind), do: :ok
  defp phase_kind(_context, _kind), do: {:error, incomplete()}

  defp terminal(run_id, kind) do
    case contained(fn -> Flows.get_tasks_by_name(terminal_name(kind), run_id) end) do
      [%Task{status: :succeeded} = task] -> {:ok, task}
      _invalid -> {:error, incomplete()}
    end
  end

  defp decode_output(:pilot_collection, raw), do: Pilot.CollectionContract.decode_output(raw)
  defp decode_output(:pilot_analysis, raw), do: Pilot.AnalysisContract.decode_output(raw)
  defp validate_output(_context, :pilot_collection, _output), do: :ok

  defp validate_output(context, :pilot_analysis, output),
    do: Pilot.Analysis.validate_output(context.revision.definition, output)

  defp fetch_run(run_id) do
    case contained(fn -> GustRepo.get(Run, run_id) end) do
      %Run{} = run -> {:ok, run}
      _missing -> {:error, incomplete()}
    end
  end

  @doc "Best-effort Gust stopping after durable application cancellation."
  @spec stop(Ecto.UUID.t()) :: :ok
  def stop(execution_id) do
    for kind <- [:pilot_collection, :pilot_analysis] do
      stop_phase(execution_id, kind)
    end

    :ok
  end

  defp stop_phase(execution_id, kind) do
    with {:ok, phase} <- Persistence.fetch_execution_phase(execution_id, kind),
         {:ok, phase_run} <- Persistence.fetch_phase_run(phase.id, :single),
         {:ok, %Run{status: status} = run} when status not in [:succeeded, :failed] <-
           stopped_pending_run(phase_run.gust_run_id) do
      Terminator.stop_run(run)
    end

    :ok
  catch
    :exit, _reason -> :ok
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

  defp unavailable, do: error("collection_unavailable", "The Pilot run is unavailable.")
  defp incomplete, do: error("collection_incomplete", "The Pilot run has not completed.")

  defp error(code, message),
    do: %Error{
      category: :unavailable,
      issues: [%Error.Issue{code: code, path: [], message: message}]
    }
end
