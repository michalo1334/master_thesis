defmodule NetworkDefense.Evaluation.Final.Contracts.SnapshotPayload do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Final.Contracts.{ComparisonEvidence, FinalError}
  alias NetworkDefense.Evaluation.Final.SchemaValidator
  alias NetworkDefense.Evaluation.JsonBoundary
  alias NetworkDefense.Evaluation.{SnapshotContract, SnapshotValidation}

  # Stored Final evidence payload.
  #
  # Database columns own the study revision, phase, schema version, and family
  # ID, so the payload never repeats them. The payload holds the crossed
  # evidence matrices and caller-asserted provenance. Analysis settings and
  # Final seeds stay in the submitted Final request; they are not evidence.
  #
  # Cross-field validation keeps the declared order authoritative: positions
  # are consecutive from zero, identities are unique, and each identity agrees
  # with its evidence matrix.

  @type t :: %__MODULE__{
          schema_version: integer(),
          evidence_role: String.t(),
          comparisons: [ComparisonEvidence.t()]
        }

  embedded_schema do
    field :schema_version, :integer
    field :evidence_role, :string
    embeds_many :comparisons, ComparisonEvidence, on_replace: :delete
  end

  def changeset(payload, attrs) do
    SnapshotContract.payload_changeset(
      payload,
      attrs,
      &SchemaValidator.matches_schema/3,
      [:comparisons]
    )
  end

  @spec parse(term()) :: {:ok, t()} | {:error, FinalError.t()}
  def parse(attrs) do
    with :ok <- string_keys_only(attrs),
         {:ok, payload} <- materialize(attrs) do
      build(payload)
    end
  end

  @spec build(t()) :: {:ok, t()} | {:error, FinalError.t()}
  def build(%__MODULE__{} = payload), do: validate_payload(payload)
  def build(_value), do: {:error, FinalError.invalid_json_value(["payload"])}

  defp materialize(attrs) when is_map(attrs) do
    SnapshotContract.materialize(
      changeset(%__MODULE__{}, attrs),
      &SchemaValidator.error_from_changeset/2,
      FinalError.changed_snapshot("The Final snapshot payload could not be materialized.")
    )
  end

  defp materialize(_attrs), do: {:error, FinalError.invalid_json_value(["payload"])}

  defp string_keys_only(attrs) do
    JsonBoundary.string_keys_only(attrs, [], &FinalError.invalid_json_value/1)
  end

  defp validate_payload(%__MODULE__{} = payload) do
    case SnapshotValidation.issues(payload.comparisons, &comparison_issues/2) do
      [] -> {:ok, payload}
      issues -> {:error, FinalError.validation_failed(issues)}
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
