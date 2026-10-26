defmodule NetworkDefense.Evaluation.Study.TaskFailure do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  @spec raise_permanent(StudyError.t()) :: no_return()
  def raise_permanent(%StudyError{} = error) do
    payload = %{
      "kind" => "network_defense.evaluation.study_error",
      "version" => 1,
      "error" => StudyError.to_params(error)
    }

    raise Gust.DAG.NonRecError, Jason.encode!(payload)
  end
end
