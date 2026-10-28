defmodule NetworkDefense.Evaluation.Study.Pipeline.Failure do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  # A bounded study error is permanent: retrying the same task cannot succeed
  # because the input, the persisted state, or the environment is wrong.
  @type bounded :: StudyError.t()

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
