defmodule NetworkDefense.Evaluation2.Study do
  @moduledoc """
  Supported context of the study evaluation subsystem.

  A study is one YAML definition. The operator freezes a revision from that
  definition, starts executions of the revision, reads their lifecycle state,
  approves the Pilot outcome, and reads the result.

  This module is the whole supported surface. It owns the short application flow
  of every operation: it reads or writes internal records through
  `Study.Persistence` and builds the returned value through `Study.Views`. The
  values are transient: `Revision`, `Status`, `PilotResult`, `Result`, and
  bounded `Error` values.

  `create_revision/1` and `start/1` are separate operations, so one frozen
  revision supports several executions.

  Scaffold: storage and scientific work return a bounded `:unavailable` error
  with the issue code `"not_implemented"` until the study pipeline exists.
  """

  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Pilot.Analysis, as: PilotAnalysis
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.PilotResult
  alias NetworkDefense.Evaluation2.Study.Result
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefense.Evaluation2.Study.Status
  alias NetworkDefense.Evaluation2.Study.Views
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

  # Scaffold only: each composed flow ends in an unimplemented storage read or
  # view builder, so these functions cannot return yet. Remove this attribute
  # together with the placeholder implementations.
  @dialyzer {:nowarn_function,
             [
               create_revision: 1,
               start: 1,
               status: 1,
               resume: 2,
               cancel: 1,
               result: 1
             ]}

  @doc """
  Freeze one study revision from YAML text.

  Revision creation owns the external checks: YAML parsing, schema checks,
  consistency checks, and graph reference lookup.
  """
  @spec create_revision(binary()) :: {:ok, Revision.t()} | {:error, Error.t()}
  def create_revision(document) do
    Persistence.create_revision(document)
    |> bind(&{:ok, Views.revision(&1)})
  end

  @doc """
  Start one execution of a frozen revision.

  The new execution begins in Pilot collection. Its later states follow the
  study lifecycle, and every valid Pilot outcome pauses before Final collection.
  """
  @spec start(revision_ref()) :: {:ok, Status.t()} | {:error, Error.t()}
  def start(%Revision{} = revision) do
    Persistence.fetch_revision(revision)
    |> bind(fn stored ->
      Persistence.start_execution(stored)
      |> bind(&{:ok, Views.status(stored, &1)})
    end)
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
    Persistence.accept_approval(execution_id, approval)
    |> bind(fn {execution, revision} -> {:ok, Views.status(revision, execution)} end)
  end

  @doc """
  Cancel one execution that is not terminal.

  Cancellation is a lifecycle event. A late phase completion leaves a cancelled
  execution cancelled.
  """
  @spec cancel(execution_id()) :: {:ok, Status.t()} | {:error, Error.t()}
  def cancel(execution_id) do
    Persistence.cancel_execution(execution_id)
    |> bind(fn {execution, revision} -> {:ok, Views.status(revision, execution)} end)
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
    |> bind(fn {execution, revision} ->
      Persistence.fetch_result(execution)
      |> bind(fn stored -> {:ok, Views.result(revision, execution, stored)} end)
    end)
  end

  # Continue one storage step with the next step.
  #
  # The scaffold's storage calls can only fail, so the success clause stays
  # unreachable until persistence is implemented.
  @dialyzer {:nowarn_function, bind: 2}
  @spec bind(
          {:ok, value} | {:error, Error.t()},
          (value -> {:ok, result} | {:error, Error.t()})
        ) :: {:ok, result} | {:error, Error.t()}
        when value: var, result: var
  defp bind(result, next) do
    case result do
      {:ok, value} -> next.(value)
      {:error, error} -> {:error, error}
    end
  end
end
