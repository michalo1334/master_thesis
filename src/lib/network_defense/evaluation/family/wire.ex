defmodule NetworkDefense.Evaluation.Family.Wire do
  @moduledoc false

  alias NetworkDefense.Evaluation.ErrorEnvelope

  alias NetworkDefense.Evaluation.Family.Contracts.{
    FamilyError,
    FamilyRequest,
    FamilyResult,
    HolmRequest
  }

  @fallback_body %{
    "code" => "workflow_failed",
    "issues" => [
      %{
        "code" => "workflow_failed",
        "path" => [],
        "message" => "The family workflow failed safely.",
        "details" => %{}
      }
    ]
  }

  def request(%FamilyRequest{} = request), do: FamilyRequest.to_params(request)

  def holm_request(%HolmRequest{} = request), do: HolmRequest.to_params(request)

  def result(%FamilyResult{} = result), do: FamilyResult.to_params(result)

  def error(%FamilyError{} = error) do
    body = ErrorEnvelope.body(error.code, error.issues, error.schema_errors, @fallback_body)

    %{"schema_version" => error.schema_version, "error" => body}
  end
end
