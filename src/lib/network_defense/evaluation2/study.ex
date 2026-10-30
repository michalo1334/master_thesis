defmodule NetworkDefense.Evaluation2.Study do
  @moduledoc """
  Supported context of the study evaluation subsystem.

  A study is one YAML definition. The operator freezes a revision from that
  definition, starts executions of the revision, reads their lifecycle state,
  approves the Pilot outcome, and reads the result.

  This module is the whole supported surface. It owns the short application flow
  of every operation: it reads or writes internal records through the internal
  persistence owners and builds the returned value through `Study.Views`. The
  values are transient: `Revision`, `Status`, `PilotResult`, `Result`, and
  bounded `Error` values.

  `create_revision/1` and `start/1` are separate operations, so one frozen
  revision supports several executions.

  Revision creation and the Pilot report still return a bounded error until the
  definition parser and the scientific analysis exist. Storage failures report
  their fixed public issue code through `Study.Views.error/1`.
  """

  use Spectral

  require Logger

  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.Executions
  alias NetworkDefense.Evaluation2.Study.Persistence.Phase
  alias NetworkDefense.Evaluation2.Study.Pilot.Analysis, as: PilotAnalysis
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.PilotResult
  alias NetworkDefense.Evaluation2.Study.Result
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefense.Evaluation2.Study.Status
  alias NetworkDefense.Evaluation2.Study.Views
  alias NetworkDefense.Evaluation2.Study.Workflow
  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  @typedoc "Declared revision identity: study identifier and revision number."
  @type revision_ref :: Revision.t()

  @typedoc "Identifier of one study execution."
  @type execution_id :: Ecto.UUID.t()

  @typedoc "Identifier of one declared Pilot candidate."
  @type candidate_id :: PilotOutcome.candidate_id()

  @typedoc "Optimization strategy of the existing optimization domain."
  @type strategy :: OptimizationParams.strategy()

  @typedoc "Approval intent: accept the recommendation or override an insufficient outcome."
  @type approval :: :recommended | {:override_insufficient, candidate_id()}

  @doc """
  Freeze one study revision from YAML text.

  Revision creation owns the external checks: YAML parsing, schema checks,
  consistency checks, and graph reference lookup.
  """
  @spec create_revision(binary()) :: {:ok, Revision.t()} | {:error, Error.t()}
  def create_revision(_document) do
    # Definition decoding and normalization arrive with the definition task. The
    # storage insert is `Persistence.insert_revision/1`.
    {:error, Placeholder.error(:create_revision)}
  end

  @doc """
  Start one execution of a frozen revision.

  The new execution begins in Pilot collection. The execution transaction commits
  first, and the call then ensures its Pilot Collection Gust run.

  A failed provisioning keeps the committed execution: the call logs the bounded
  failure and returns the status, so the caller keeps the execution identifier
  for a later retry. The status is the refreshed row, or the last committed
  snapshot when that refresh fails.
  """
  @spec start(revision_ref()) :: {:ok, Status.t()} | {:error, Error.t()}
  def start(%Revision{} = revision) do
    case started_execution(revision) do
      {:ok, %{active_phase: %Phase{} = phase} = context} ->
        ensure_pilot_collection(context, phase.id)

      {:error, _failure} = failure ->
        failure
    end
  end

  @doc """
  Read the lifecycle state of one execution.

  Status joins the execution row with its revision. Gust run detail stays
  internal.
  """
  @spec status(execution_id()) :: {:ok, Status.t()} | {:error, Error.t()}
  def status(execution_id) do
    Persistence.fetch_execution(execution_id)
    |> bind(fn {execution, revision} -> {:ok, Views.status(revision, execution)} end)
  end

  @doc """
  Read the complete Pilot report of one execution.

  The report holds the compact outcome and every candidate with its per
  comparison assessment. Approval uses this report, and an insufficient outcome
  is explained by it.
  """
  @spec pilot_result(execution_id()) :: {:ok, PilotResult.t()} | {:error, Error.t()}
  def pilot_result(execution_id), do: PilotAnalysis.report(execution_id)

  @doc """
  Approve the Pilot outcome and start Final collection.

  The approval states intent only. Resume resolves the declared candidate and
  freezes its two sample counts. An invalid approval leaves the execution
  waiting for approval.
  """
  @spec resume(execution_id(), approval()) :: {:ok, Status.t()} | {:error, Error.t()}
  def resume(execution_id, approval) do
    Executions.accept_approval(execution_id, approval)
    |> bind(fn context -> {:ok, Views.status(context.revision, context.execution)} end)
  end

  @doc """
  Cancel one execution that is not terminal.

  Cancellation is a lifecycle event. A late phase completion leaves a cancelled
  execution cancelled.
  """
  @spec cancel(execution_id()) :: {:ok, Status.t()} | {:error, Error.t()}
  def cancel(execution_id) do
    Executions.cancel_execution(execution_id)
    |> bind(fn context -> {:ok, Views.status(context.revision, context.execution)} end)
  end

  @doc """
  Read the result of one successful execution.

  The result joins the execution-owned Pilot history with the Final-owned
  corrected family and measured timing. A read before success returns a bounded
  error.
  """
  @spec result(execution_id()) :: {:ok, Result.t()} | {:error, Error.t()}
  def result(execution_id) do
    Persistence.fetch_execution(execution_id)
    |> bind(fn {execution, revision} -> stored_result(execution, revision) end)
  end

  # The public result exists only for a successful execution.
  #
  # The success check happens before the immutable result is read, so the view
  # joins one successful execution with its own stored result.
  defp stored_result(%Persistence.Execution{state: :succeeded} = execution, revision) do
    Persistence.fetch_result(execution.id)
    |> bind(&Views.result(revision, execution, &1))
  end

  defp stored_result(_execution, _revision), do: {:error, Views.result_unavailable()}

  # Continue one storage step with the next step.
  #
  # A storage failure crosses the public boundary once, through the shared error
  # mapping of `Study.Views`.
  @spec bind(
          Persistence.response(value),
          (value -> {:ok, result} | {:error, Error.t()})
        ) :: {:ok, result} | {:error, Error.t()}
        when value: var, result: var
  defp bind(result, next) do
    case result do
      {:ok, value} -> next.(value)
      {:error, failure} -> {:error, Views.error(failure)}
    end
  end

  # The committed execution keeps its state. Only the storage failure is mapped
  # into the bounded public error.
  @spec started_execution(revision_ref()) ::
          {:ok, Persistence.lifecycle_context()} | {:error, Error.t()}
  defp started_execution(revision) do
    case Executions.start_execution(revision) do
      {:ok, context} -> {:ok, context}
      {:error, failure} -> {:error, Views.error(failure)}
    end
  end

  # The execution is committed, so a bounded provisioning failure becomes a logged
  # outcome and the caller still receives the execution identifier in the status.
  @spec ensure_pilot_collection(Persistence.lifecycle_context(), Ecto.UUID.t()) ::
          {:ok, Status.t()} | {:error, Error.t()}
  defp ensure_pilot_collection(context, phase_id) do
    case Workflow.ensure_pilot_collection_run(phase_id) do
      {:ok, _phase_run} ->
        status(context.execution.id)

      {:error, failure} ->
        Logger.error("Evaluation2 Pilot collection provisioning failed",
          error: inspect(failure)
        )

        refresh_or_committed_status(context)
    end
  end

  # A failed refresh must not hide the committed execution, so the committed
  # context becomes the returned status. It is the last committed snapshot.
  @spec refresh_or_committed_status(Persistence.lifecycle_context()) ::
          {:ok, Status.t()} | {:error, Error.t()}
  defp refresh_or_committed_status(context) do
    case status(context.execution.id) do
      {:ok, _status} = current ->
        current

      {:error, failure} ->
        Logger.error("Evaluation2 study status refresh failed", error: inspect(failure))
        {:ok, Views.status(context.revision, context.execution)}
    end
  end
end
