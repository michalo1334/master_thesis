defmodule NetworkDefense.Evaluation.Final.Contracts.SnapshotInput do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, SnapshotPayload}
  alias NetworkDefense.Evaluation.Final.{SchemaValidator, SnapshotLimits}
  alias NetworkDefense.Evaluation.JsonBoundary
  alias NetworkDefense.Evaluation.SnapshotContract

  # Create document for one immutable Final evidence snapshot.
  #
  # Version 1 is Final-only. The public path rejects `phase = "pilot"` and
  # `evidence_role = "pilot"` in the schema, so the accepted Pilot snapshot
  # contract and the Final snapshot contract cannot substitute for each other.
  #
  @type t :: %__MODULE__{
          study_revision_id: String.t(),
          phase: String.t(),
          schema_version: integer(),
          family_id: String.t(),
          payload: SnapshotPayload.t()
        }

  embedded_schema do
    field :study_revision_id, :string
    field :phase, :string
    field :schema_version, :integer
    field :family_id, :string
    embeds_one :payload, SnapshotPayload, on_replace: :update
  end

  @spec parse(term()) :: {:ok, t()} | {:error, FinalError.t()}
  def parse(attrs) do
    with :ok <- string_keys_only(attrs),
         {:ok, input} <- materialize(attrs),
         {:ok, input} <- normalize_uuid(input),
         {:ok, limits} <- SnapshotLimits.limits(),
         {:ok, payload} <- SnapshotPayload.build(input.payload),
         :ok <- SnapshotLimits.validate(payload, limits) do
      {:ok, %{input | payload: payload}}
    end
  end

  def changeset(input, attrs) do
    SnapshotContract.input_changeset(input, attrs, &SchemaValidator.matches_schema/3)
  end

  # The schema-gated changeset owns the one snapshot schema traversal. A value
  # that is not a map fails the same gate and reports the same bounded
  # diagnostics as any other schema violation.
  defp materialize(attrs) do
    changeset = changeset(%__MODULE__{}, attrs)

    case apply_action(changeset, :validate) do
      {:ok, input} ->
        {:ok, input}

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           FinalError.changed_snapshot("The Final snapshot input could not be materialized.")
         )}
    end
  end

  defp string_keys_only(attrs),
    do: JsonBoundary.string_keys_only(attrs, [], &FinalError.invalid_json_value/1)

  defp normalize_uuid(%__MODULE__{} = input) do
    case Ecto.UUID.cast(input.study_revision_id) do
      {:ok, uuid} -> {:ok, %{input | study_revision_id: uuid}}
      :error -> {:error, FinalError.invalid_identifier(["study_revision_id"])}
    end
  end
end
