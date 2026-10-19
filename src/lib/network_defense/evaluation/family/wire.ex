defmodule NetworkDefense.Evaluation.Family.Wire do
  @moduledoc false

  alias NetworkDefense.Evaluation.Family.Contracts.{
    FamilyError,
    FamilyRequest,
    FamilyResult,
    HolmRequest
  }

  def request(%FamilyRequest{} = request), do: FamilyRequest.to_params(request)

  def holm_request(%HolmRequest{} = request), do: HolmRequest.to_params(request)

  def result(%FamilyResult{} = result), do: FamilyResult.to_params(result)

  def error(%FamilyError{} = error) do
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
      "message" => "The family workflow failed safely.",
      "details" => %{}
    }
  end
end
