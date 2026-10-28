defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Snapshot.SchemaValidator do
  @moduledoc false

  @type kind :: :snapshot | :snapshot_payload

  # JSON Schema gate for stored Final evidence snapshots.
  #
  # Both documents belong to one trust boundary: the snapshot envelope and the
  # stored payload are decoded from a database row, so they are validated before
  # any typed value exists.
  use NetworkDefense.Evaluation.Study.Pipeline.SchemaGate,
    dir: "priv/evaluation/final/v1/schemas",
    error: NetworkDefense.Evaluation.Study.Pipeline.Final.Error,
    tag: :final_error,
    schemas: [
      snapshot: {"snapshot.schema.json", :document},
      snapshot_payload: {"snapshot.schema.json", :payload}
    ]

  @impl true
  def safe_error(:snapshot),
    do: generic_schema_error("Final snapshot validation failed safely.")

  def safe_error(:snapshot_payload),
    do: generic_schema_error("Stored Final evidence validation failed safely.")

  def safe_error(_kind), do: Error.invalid_response_contract()
end
