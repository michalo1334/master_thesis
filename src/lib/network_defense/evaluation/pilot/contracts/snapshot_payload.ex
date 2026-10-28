defmodule NetworkDefense.Evaluation.Pilot.Contracts.SnapshotPayload do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.JsonBoundary

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    ComparisonEvidence,
    PilotError,
    RuntimeEvidence
  }

  alias NetworkDefense.Evaluation.Pilot.SchemaValidator
  alias NetworkDefense.Evaluation.{SnapshotContract, SnapshotValidation}

  # Stored snapshot payload. Database columns own the study revision, phase,
  # schema version, and family ID, so the payload never repeats them.
  #
  # Cross-field validation keeps the declared order authoritative: positions
  # are consecutive from zero, identities are unique, and each identity agrees
  # with its evidence matrix.

  @type t :: %__MODULE__{
          schema_version: integer(),
          evidence_role: String.t(),
          comparisons: [ComparisonEvidence.t()],
          runtime_evidence: RuntimeEvidence.t()
        }

  embedded_schema do
    field :schema_version, :integer
    field :evidence_role, :string
    embeds_many :comparisons, ComparisonEvidence, on_replace: :delete
    embeds_one :runtime_evidence, RuntimeEvidence, on_replace: :update
  end

  def changeset(payload, attrs) do
    SnapshotContract.payload_changeset(
      payload,
      attrs,
      &SchemaValidator.matches_schema/3,
      [:comparisons, :runtime_evidence]
    )
  end

  @spec parse(term()) :: {:ok, t()} | {:error, PilotError.t()}
  def parse(attrs) do
    with :ok <- string_keys_only(attrs),
         {:ok, payload} <- materialize(attrs) do
      build(payload)
    end
  end

  @spec build(t()) :: {:ok, t()} | {:error, PilotError.t()}
  def build(%__MODULE__{} = payload), do: validate_payload(payload)
  def build(_value), do: {:error, PilotError.invalid_json_value(["payload"])}

  defp materialize(attrs) when is_map(attrs) do
    SnapshotContract.materialize(
      changeset(%__MODULE__{}, attrs),
      &SchemaValidator.error_from_changeset/2,
      PilotError.changed_snapshot("The snapshot payload could not be materialized.")
    )
  end

  defp materialize(_attrs), do: {:error, PilotError.invalid_json_value(["payload"])}

  defp string_keys_only(attrs) do
    JsonBoundary.string_keys_only(attrs, [], &PilotError.invalid_json_value/1)
  end

  defp validate_payload(%__MODULE__{} = payload) do
    case SnapshotValidation.issues(payload.comparisons, &comparison_issues/2) do
      [] -> {:ok, payload}
      issues -> {:error, PilotError.validation_failed(issues)}
    end
  end

  defp comparison_issues(%ComparisonEvidence{} = comparison, index) do
    SnapshotValidation.comparison_issues(
      comparison.position,
      comparison.identity,
      comparison.evidence,
      index
    )
  end
end
