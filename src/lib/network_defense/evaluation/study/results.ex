defmodule NetworkDefense.Evaluation.Study.Results do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Result, as: CompactResult
  alias NetworkDefense.Evaluation.Study.Pipeline.Result.Store

  @spec get_for_execution(Ecto.UUID.t()) ::
          {:ok, CompactResult.t()} | {:error, StudyError.t()}
  def get_for_execution(execution_id), do: Store.get_for_execution(execution_id)
end
