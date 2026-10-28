defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Wire do
  @moduledoc false

  alias NetworkDefense.Evaluation.ErrorEnvelope
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Contracts.Request
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Contracts.Result
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Error, as: FinalError

  @fallback_body %{
    "code" => "workflow_failed",
    "issues" => [
      %{
        "code" => "workflow_failed",
        "path" => [],
        "message" => "The Final workflow failed safely.",
        "details" => %{}
      }
    ]
  }

  def request(%Request{} = request), do: Request.to_params(request)

  def result(%Result{} = result), do: Result.to_params(result)

  def error(%FinalError{} = error) do
    body = ErrorEnvelope.body(error.code, error.issues, error.schema_errors, @fallback_body)

    %{"schema_version" => error.schema_version, "error" => body}
  end
end
