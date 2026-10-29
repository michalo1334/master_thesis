defmodule NetworkDefense.Evaluation2 do
  @moduledoc """
  Public entry point of the replacement study evaluation subsystem.

  A study is one YAML definition. The operator freezes a revision from that
  definition, starts executions of the revision, observes their lifecycle,
  approves the Pilot outcome, and reads the stored result. Comparison and family
  calculations stay internal to the study path.

  The contract is identifier based. Callers pass a revision, an execution, and
  one selection value in, and receive a stored record or a bounded error back.
  Gust runs, phase records, evidence snapshots, and collection items stay behind
  this boundary.

  Scaffold: the functions below describe the intended boundary. Each one returns
  `{:error, :not_implemented}` until the study pipeline exists, while the deeper
  scaffold modules still raise `NetworkDefense.Evaluation2.NotImplementedError`.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation2.Study.{Cancel, Executions, Result, Resume, Revisions}
  alias NetworkDefense.Evaluation2.{StudyExecution, StudyResult, StudyRevision}

  @typedoc "Identifier of one frozen study revision."
  @type revision_id :: Ecto.UUID.t()

  @typedoc "Identifier of one study execution."
  @type execution_id :: Ecto.UUID.t()

  @typedoc "Approval input: accept the Pilot recommendation or override an insufficient outcome."
  @type final_selection :: Resume.final_selection()

  @doc """
  Freeze one study definition from YAML text.

  The returned revision is the immutable input of every later execution. The
  full creation contract (YAML parsing, schema checks, consistency, and graph
  lookup) belongs to this external boundary.
  """
  @spec create_study_revision(binary()) ::
          {:ok, StudyRevision.t()} | {:error, StudyError.t() | :not_implemented}
  def create_study_revision(document), do: Revisions.create(document)

  @doc """
  Start one execution of a frozen revision.

  The new execution begins in the Pilot collection phase. Its later states are
  the declared lifecycle states of `NetworkDefense.Evaluation2.Study.Lifecycle`.
  """
  @spec start_study(revision_id()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t() | :not_implemented}
  def start_study(revision_id), do: Executions.start(revision_id)

  @doc """
  Read the current lifecycle record of one execution.

  Status reads the execution only. Gust run state and task history stay behind
  the phase records.
  """
  @spec study_status(execution_id()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t() | :not_implemented}
  def study_status(execution_id), do: Executions.status(execution_id)

  @doc """
  Approve the Pilot outcome and start Final collection.

  A valid selection freezes the declared candidate in the execution. An invalid
  selection leaves the execution waiting for approval.
  """
  @spec resume_study(execution_id(), final_selection()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t() | :not_implemented}
  def resume_study(execution_id, selection), do: Resume.accept(execution_id, selection)

  @doc """
  Cancel one execution that is not terminal.

  Cancellation is a lifecycle event. A late phase completion cannot advance a
  cancelled execution.
  """
  @spec cancel_study(execution_id()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t() | :not_implemented}
  def cancel_study(execution_id), do: Cancel.cancel(execution_id)

  @doc """
  Read the stored result of one successful execution.

  The result holds the compact Pilot outcome, the frozen selection, the
  corrected Final family, and the measured timing.
  """
  @spec study_result(execution_id()) ::
          {:ok, StudyResult.t()} | {:error, StudyError.t() | :not_implemented}
  def study_result(execution_id), do: Result.get(execution_id)
end
