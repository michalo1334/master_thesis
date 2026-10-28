defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.SchemaValidator do
  @moduledoc false

  @type kind :: :request | :result

  # JSON Schema gate for the Final analysis boundary.
  #
  # The request is decoded from persisted run parameters and the result is
  # decoded from a stored task result. Both checks run on serialized data,
  # before a typed value exists.
  use NetworkDefense.Evaluation.Study.Pipeline.SchemaGate,
    dir: "priv/evaluation/final/v1/schemas",
    error: NetworkDefense.Evaluation.Study.Pipeline.Final.Error,
    tag: :final_error,
    schemas: [
      request: {"request.schema.json", :document},
      result: {"result.schema.json", :document}
    ]

  @impl true
  def safe_error(:request), do: generic_schema_error("Final request validation failed safely.")

  def safe_error(_kind), do: Error.invalid_response_contract()
end
