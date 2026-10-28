defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.SchemaValidator do
  @moduledoc false

  @type kind :: :error

  # JSON Schema gate for one shared Pilot value: the serialized error envelope
  # that every Pilot boundary persists.
  #
  # Snapshot and analysis values are validated by the gate of the boundary that
  # owns them.
  use NetworkDefense.Evaluation.Study.Pipeline.SchemaGate,
    dir: "priv/evaluation/pilot/v1/schemas",
    error: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error,
    tag: :pilot_error,
    schemas: [error: {"error.schema.json", :document}]

  @impl true
  def safe_error(:error), do: Error.invalid_response_contract()
end
