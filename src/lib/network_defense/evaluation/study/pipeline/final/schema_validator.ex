defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.SchemaValidator do
  @moduledoc false

  @type kind :: :error

  # JSON Schema gate for one shared Final value: the serialized error envelope
  # that every Final boundary persists.
  #
  # Snapshot and analysis values are validated by the gate of the boundary that
  # owns them.
  use NetworkDefense.Evaluation.Study.Pipeline.SchemaGate,
    dir: "priv/evaluation/final/v1/schemas",
    error: NetworkDefense.Evaluation.Study.Pipeline.Final.Error,
    tag: :final_error,
    schemas: [error: {"error.schema.json", :document}]

  @impl true
  def safe_error(:error), do: Error.invalid_response_contract()

  def safe_error(_kind), do: Error.invalid_response_contract()
end
