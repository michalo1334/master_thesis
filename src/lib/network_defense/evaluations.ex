defmodule NetworkDefense.Evaluations do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
  alias NetworkDefense.Evaluation.Comparison.{Wire, Workflow}
  alias NetworkDefense.Evaluation.Family
  alias NetworkDefense.Evaluation.Family.Contracts.FamilyRequest
  alias NetworkDefense.Evaluation.Study.Cancel
  alias NetworkDefense.Evaluation.Study.CompactResult
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Results
  alias NetworkDefense.Evaluation.Study.Resume
  alias NetworkDefense.Evaluation.Study.Revisions
  alias NetworkDefense.Evaluation.Study.Start
  alias NetworkDefense.Evaluation.Study.Status
  alias NetworkDefense.Evaluation.{StudyExecution, StudyRevision}

  # The public evaluation facade.
  #
  # Three public groups remain: the study lifecycle, the comparison workflow,
  # and the family workflow. The Pilot and Final workflows stay internal to the
  # study coordinator, so callers never control Gust runs, evidence snapshots,
  # collection items, evidence matrices, or task history directly.

  def submit_comparison(attrs) do
    with {:ok, request} <- ComparisonRequest.parse(attrs) do
      request
      |> Wire.request()
      |> Workflow.submit()
    end
  end

  def await_comparison(run_id, timeout_ms), do: Workflow.await(run_id, timeout_ms)
  def get_comparison_result(run_id), do: Workflow.result(run_id)

  def submit_family(attrs) do
    with {:ok, request} <- FamilyRequest.parse(attrs) do
      request
      |> Family.Wire.request()
      |> Family.Workflow.submit()
    end
  end

  def await_family(run_id, timeout_ms), do: Family.Workflow.await(run_id, timeout_ms)
  def get_family_result(run_id), do: Family.Workflow.result(run_id)

  @type final_selection :: Resume.final_selection()

  @spec create_study_revision(binary()) ::
          {:ok, StudyRevision.t()} | {:error, StudyError.t()}
  def create_study_revision(document), do: Revisions.create(document)

  @spec start_study(Ecto.UUID.t()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def start_study(revision_id), do: Start.start(revision_id)

  @spec study_status(Ecto.UUID.t()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def study_status(execution_id), do: Status.get(execution_id)

  @spec resume_study(Ecto.UUID.t(), final_selection()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def resume_study(execution_id, selection), do: Resume.resume(execution_id, selection)

  @spec cancel_study(Ecto.UUID.t()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def cancel_study(execution_id), do: Cancel.cancel(execution_id)

  @spec study_result(Ecto.UUID.t()) ::
          {:ok, CompactResult.t()} | {:error, StudyError.t()}
  def study_result(execution_id), do: Results.get_for_execution(execution_id)
end
