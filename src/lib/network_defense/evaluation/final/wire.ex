defmodule NetworkDefense.Evaluation.Final.Wire do
  @moduledoc false

  alias NetworkDefense.Evaluation.ErrorEnvelope
  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request, Result}

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
