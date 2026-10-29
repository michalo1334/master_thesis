defmodule NetworkDefense.Evaluation2.Study do
  @moduledoc """
  Supported entry point of the study evaluation subsystem.

  A study is one YAML definition. The operator freezes a revision from that
  definition, starts executions of the revision, reads their lifecycle state,
  approves the Pilot outcome, and reads the result.

  The boundary returns transient values: `Revision`, `Status`, `PilotResult`,
  `Result`, and bounded `Error` values. Revision storage, executions, phase
  records, Gust runs, evidence snapshots, and collection items stay internal.

  `create_revision/1` and `start/1` are separate operations. One frozen revision
  supports several executions.

  Scaffold: each operation delegates to an internal operation that returns a
  bounded `:unavailable` error with the issue code `"not_implemented"` until the
  study pipeline exists. Internal constructor and bang operations raise
  `NetworkDefense.Evaluation2.NotImplementedError` instead.
  """

  alias NetworkDefense.Evaluation2.Study.{
    Cancel,
    Error,
    Executions,
    Pilot,
    PilotOutcome,
    PilotResult,
    Result,
    Results,
    Resume,
    Revision,
    Revisions,
    Status
  }

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
  def create_revision(document), do: Revisions.create(document)

  @doc """
  Start one execution of a frozen revision.

  The new execution begins in Pilot collection. Its later states follow the
  study lifecycle, and every valid Pilot outcome pauses before Final collection.
  """
  @spec start(revision_ref()) :: {:ok, Status.t()} | {:error, Error.t()}
  def start(%Revision{} = revision), do: Executions.start(revision)

  @doc """
  Read the lifecycle state of one execution.

  Status reads the execution and its revision only. Gust run detail stays
  internal.
  """
  @spec status(execution_id()) :: {:ok, Status.t()} | {:error, Error.t()}
  def status(execution_id), do: Executions.status(execution_id)

  @doc """
  Read the complete Pilot report of one execution.

  The report holds the compact outcome and every candidate with its per
  comparison assessment. Approval uses this report, and an insufficient outcome
  is explained by it.
  """
  @spec pilot_result(execution_id()) :: {:ok, PilotResult.t()} | {:error, Error.t()}
  def pilot_result(execution_id), do: Pilot.Analysis.report(execution_id)

  @doc """
  Approve the Pilot outcome and start Final collection.

  The approval states intent only. Resume resolves the declared candidate and
  freezes its two sample counts. An invalid approval leaves the execution
  waiting for approval.
  """
  @spec resume(execution_id(), approval()) :: {:ok, Status.t()} | {:error, Error.t()}
  def resume(execution_id, approval), do: Resume.accept(execution_id, approval)

  @doc """
  Cancel one execution that is not terminal.

  Cancellation is a lifecycle event. A late phase completion leaves a cancelled
  execution cancelled.
  """
  @spec cancel(execution_id()) :: {:ok, Status.t()} | {:error, Error.t()}
  def cancel(execution_id), do: Cancel.cancel(execution_id)

  @doc """
  Read the result of one successful execution.

  The result joins the execution-owned Pilot history with the Final-owned
  corrected family and measured timing. A read before success returns a bounded
  error.
  """
  @spec result(execution_id()) :: {:ok, Result.t()} | {:error, Error.t()}
  def result(execution_id), do: Results.get(execution_id)
end
