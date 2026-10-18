defmodule NetworkDefense.Evaluation.Comparison.Wire do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{
    ComparisonError,
    ComparisonRequest,
    ComparisonStatistics
  }

  def request(%ComparisonRequest{} = request), do: ComparisonRequest.to_params(request)

  def statistics(%ComparisonStatistics{} = statistics),
    do: ComparisonStatistics.to_params(statistics)

  def error(%ComparisonError{} = error) do
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
      "message" => "The comparison workflow failed safely.",
      "details" => %{}
    }
  end
end
