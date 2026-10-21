defmodule NetworkDefense.Evaluation.Pilot.Wire do
  @moduledoc false

  alias NetworkDefense.Evaluation.ErrorEnvelope

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    CandidateComparisonRequest,
    PilotError,
    PilotRequest,
    PilotResult
  }

  @fallback_body %{
    "code" => "workflow_failed",
    "issues" => [
      %{
        "code" => "workflow_failed",
        "path" => [],
        "message" => "The pilot workflow failed safely.",
        "details" => %{}
      }
    ]
  }

  def request(%PilotRequest{} = request), do: PilotRequest.to_params(request)

  def candidate_request(%CandidateComparisonRequest{} = request),
    do: CandidateComparisonRequest.to_params(request)

  def result(%PilotResult{} = result), do: PilotResult.to_params(result)

  def error(%PilotError{} = error) do
    body = ErrorEnvelope.body(error.code, error.issues, error.schema_errors, @fallback_body)

    %{"schema_version" => error.schema_version, "error" => body}
  end
end
