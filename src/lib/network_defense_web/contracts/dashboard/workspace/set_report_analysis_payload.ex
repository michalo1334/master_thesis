defmodule NetworkDefenseWeb.Web.Contracts.SetReportAnalysisPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workspace

  embedded_schema do
    field :kind, :string
    field :report_id, :string
    field :analysis_id, :string
  end

  @type t :: %__MODULE__{kind: String.t(), report_id: String.t(), analysis_id: String.t() | nil}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:kind, :report_id, :analysis_id])
    |> validate_required([:kind, :report_id])
    |> validate_inclusion(:kind, ["simulation_report", "optimization_report"])
    |> Contracts.validate_uuid(:report_id)
    |> validate_optional_uuid(:analysis_id)
  end

  defp validate_optional_uuid(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_nil(value) or Ecto.UUID.cast(value) != :error, do: [], else: [{field, "is invalid"}]
    end)
  end
end
