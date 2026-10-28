defmodule NetworkDefense.Evaluation.SnapshotContract do
  @moduledoc false

  import Ecto.Changeset

  def payload_changeset(payload, attrs, matches_schema, required_embeds) do
    payload
    |> change()
    |> matches_schema.(attrs, :snapshot_payload)
    |> cast_if_schema_valid(attrs, [:schema_version, :evidence_role], required_embeds)
  end

  def input_changeset(input, attrs, matches_schema) do
    input
    |> change()
    |> matches_schema.(attrs, :snapshot)
    |> cast_if_schema_valid(
      attrs,
      [:study_revision_id, :phase, :schema_version, :family_id],
      [:payload]
    )
  end

  def comparison_changeset(comparison, attrs) do
    comparison
    |> cast(attrs, [:position])
    |> cast_embed(:identity, required: true)
    |> cast_embed(:evidence, required: true)
    |> cast_embed(:provenance, required: true)
  end

  def materialize(changeset, error_from_changeset, fallback) do
    case apply_action(changeset, :validate) do
      {:ok, value} -> {:ok, value}
      {:error, changeset} -> {:error, error_from_changeset.(changeset, fallback)}
    end
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs, _fields, _embeds),
    do: changeset

  defp cast_if_schema_valid(changeset, attrs, fields, embeds) do
    changeset = cast(changeset, attrs, fields)
    Enum.reduce(embeds, changeset, &cast_embed(&2, &1, required: true))
  end
end
