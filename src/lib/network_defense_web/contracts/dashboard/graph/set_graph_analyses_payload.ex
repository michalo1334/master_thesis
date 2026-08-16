defmodule NetworkDefenseWeb.Web.Contracts.SetGraphAnalysesPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :graph_revision_id, :string
    field :analysis_ids, {:array, :string}, default: []
  end

  @type t :: %__MODULE__{graph_revision_id: String.t(), analysis_ids: [String.t()]}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_revision_id, :analysis_ids])
    |> validate_required([:graph_revision_id])
    |> Contracts.validate_uuid(:graph_revision_id)
    |> validate_uuid_list(:analysis_ids)
  end

  defp validate_uuid_list(changeset, field) do
    validate_change(changeset, field, fn ^field, values ->
      if Enum.all?(values, &(Ecto.UUID.cast(&1) != :error)),
        do: [],
        else: [{field, "contains an invalid UUID"}]
    end)
  end
end
