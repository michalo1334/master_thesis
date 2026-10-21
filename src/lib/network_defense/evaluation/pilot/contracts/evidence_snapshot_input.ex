defmodule NetworkDefense.Evaluation.Pilot.Contracts.EvidenceSnapshotInput do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.JsonBoundary
  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotError, SnapshotPayload}
  alias NetworkDefense.Evaluation.Pilot.{Limits, SchemaValidator, SnapshotLimits}

  # Create document for one immutable Pilot evidence snapshot.
  #
  # Version 1 is Pilot-only. The public path rejects `phase = "final"` and
  # `evidence_role = "final"` in the schema. The database check may reserve
  # `final` for a separately approved contract, but no Stage 4 path creates or
  # analyzes Final evidence.
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

  @spec parse(term()) :: {:ok, t()} | {:error, PilotError.t()}
  def parse(attrs) do
    with :ok <- string_keys_only(attrs),
         :ok <- SchemaValidator.validate(:snapshot, attrs),
         {:ok, input} <- materialize(attrs),
         {:ok, input} <- normalize_uuid(input),
         {:ok, limits} <- Limits.fetch(),
         {:ok, payload} <- SnapshotPayload.build(input.payload),
         :ok <- SnapshotLimits.validate(payload, limits) do
      {:ok, %{input | payload: payload}}
    end
  end

  def changeset(input, attrs) do
    input
    |> change()
    |> SchemaValidator.matches_schema(attrs, :snapshot)
    |> cast_if_schema_valid(attrs)
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs), do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [:study_revision_id, :phase, :schema_version, :family_id])
    |> cast_embed(:payload, required: true)
  end

  defp materialize(attrs) when is_map(attrs) do
    changeset = changeset(%__MODULE__{}, attrs)

    case apply_action(changeset, :validate) do
      {:ok, input} ->
        {:ok, input}

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           PilotError.changed_snapshot("The snapshot input could not be materialized.")
         )}
    end
  end

  defp materialize(_attrs), do: {:error, PilotError.invalid_json_value([])}

  defp string_keys_only(attrs),
    do: JsonBoundary.string_keys_only(attrs, [], &PilotError.invalid_json_value/1)

  defp normalize_uuid(%__MODULE__{} = input) do
    case Ecto.UUID.cast(input.study_revision_id) do
      {:ok, uuid} -> {:ok, %{input | study_revision_id: uuid}}
      :error -> {:error, PilotError.invalid_identifier(["study_revision_id"])}
    end
  end
end
