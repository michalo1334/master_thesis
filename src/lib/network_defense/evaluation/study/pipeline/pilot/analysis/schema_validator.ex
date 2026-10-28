defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.SchemaValidator do
  @moduledoc false

  @type kind :: :request | :candidate_request | :candidate_response | :result

  # JSON Schema gate for the Pilot analysis boundary.
  #
  # The request is decoded from persisted run parameters, the candidate request
  # and response cross the compute service, and the result is decoded from a
  # stored task result. Every check runs on serialized data, before a typed
  # value exists.
  use NetworkDefense.Evaluation.Study.Pipeline.SchemaGate,
    dir: "priv/evaluation/pilot/v1/schemas",
    error: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error,
    tag: :pilot_error,
    schemas: [
      request: {"request.schema.json", :document},
      candidate_request: {"candidate_request.schema.json", :document},
      candidate_response: {"candidate_response.schema.json", :document},
      result: {"result.schema.json", :document}
    ]

  @impl true
  def safe_error(:request), do: generic_schema_error("Pilot request validation failed safely.")

  def safe_error(_kind), do: Error.invalid_response_contract()
end
