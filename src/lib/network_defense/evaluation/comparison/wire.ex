defmodule NetworkDefense.Evaluation.Comparison.Wire do
  @moduledoc false

  alias NetworkDefense.Evaluation.ErrorEnvelope

  alias NetworkDefense.Evaluation.Comparison.Contracts.{
    ComparisonError,
    ComparisonRequest,
    ComparisonStatistics
  }

  @fallback_body %{
    "code" => "workflow_failed",
    "issues" => [
      %{
        "code" => "workflow_failed",
        "path" => [],
        "message" => "The comparison workflow failed safely.",
        "details" => %{}
      }
    ]
  }

  def request(%ComparisonRequest{} = request), do: ComparisonRequest.to_params(request)

  def statistics(%ComparisonStatistics{} = statistics),
    do: ComparisonStatistics.to_params(statistics)

  def error(%ComparisonError{} = error) do
    body = ErrorEnvelope.body(error.code, error.issues, error.schema_errors, @fallback_body)

    %{"schema_version" => error.schema_version, "error" => body}
  end
end
