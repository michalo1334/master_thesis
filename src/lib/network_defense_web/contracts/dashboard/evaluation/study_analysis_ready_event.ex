defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyAnalysisReadyEvent do
  @moduledoc """
  One completed Pilot or Final result.

  `archive` holds the exact result ZIP bytes encoded as base64. The encoding is
  the transient browser boundary: the LiveView encodes the ZIP, pushes this
  event once, and then keeps only the parsed analysis. The server does not
  persist the ZIP. `NetworkDefense.Evaluation.AnalysisLimits.browser_result_bytes/0`
  bounds the ZIP size; an oversized result becomes an error event with code
  `result_too_large` instead.

  `attempt_id` repeats the opaque identity from the accepted start reply. The
  browser accepts this event only when the document, mode, and attempt all
  match, so a delayed result from an earlier attempt cannot settle a retry.
  """

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysis

  @enum_values mode: [:pilot, :final]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :document_id, :string
    field :mode, :string
    field :attempt_id, :string
    field :archive, :string
    field :pilot_eligible, :boolean
    embeds_one :analysis, EvaluationAnalysis
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          mode: String.t(),
          attempt_id: String.t(),
          archive: String.t(),
          pilot_eligible: boolean() | nil,
          analysis: EvaluationAnalysis.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :mode, :attempt_id, :archive, :pilot_eligible])
    |> cast_embed(:analysis)
    |> validate_required([:document_id, :mode, :attempt_id, :archive, :analysis])
    |> validate_inclusion(:mode, ["pilot", "final"])
    |> Contracts.validate_uuid(:document_id)
  end
end
