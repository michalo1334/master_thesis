defmodule NetworkDefense.Evaluation.Pilot.Wire do
  @moduledoc false

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    CandidateComparisonRequest,
    PilotError,
    PilotRequest,
    PilotResult
  }

  def request(%PilotRequest{} = request), do: PilotRequest.to_params(request)

  def candidate_request(%CandidateComparisonRequest{} = request),
    do: CandidateComparisonRequest.to_params(request)

  def result(%PilotResult{} = result), do: PilotResult.to_params(result)

  def error(%PilotError{} = error) do
    body =
      cond do
        error.issues != [] ->
          %{"code" => error.code, "issues" => error.issues}

        error.schema_errors != [] ->
          %{"code" => error.code, "schema_errors" => error.schema_errors}

        true ->
          %{"code" => "workflow_failed", "issues" => [fallback_issue()]}
      end

    %{"schema_version" => error.schema_version, "error" => body}
  end

  defp fallback_issue do
    %{
      "code" => "workflow_failed",
      "path" => [],
      "message" => "The pilot workflow failed safely.",
      "details" => %{}
    }
  end
end
