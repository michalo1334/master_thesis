defmodule NetworkDefense.Evaluation.Study.Results do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Contracts.Result, as: FinalResult
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.TimingSummary
  alias NetworkDefense.Evaluation.Study.Pipeline.Result, as: CompactResult
  alias NetworkDefense.Evaluation.Study.Pipeline.Result.Store
  alias NetworkDefense.Evaluation.StudyExecution

  # The public study-result boundary.
  #
  # Storage, lifecycle completion, and read-back validation belong to the
  # pipeline result store. This module keeps the two study-facing entry points.

  @spec create_success(StudyExecution.t(), FinalResult.t(), TimingSummary.t() | nil) ::
          {:ok, CompactResult.t()} | {:stop, atom()} | {:error, StudyError.t()}
  def create_success(%StudyExecution{} = execution, %FinalResult{} = final_result, timing) do
    Store.create_success(execution, final_result, timing)
  end

  @spec get_for_execution(Ecto.UUID.t()) ::
          {:ok, CompactResult.t()} | {:error, StudyError.t()}
  def get_for_execution(execution_id), do: Store.get_for_execution(execution_id)
end
