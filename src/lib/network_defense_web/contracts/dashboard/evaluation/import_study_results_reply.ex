defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ImportStudyResultsReply do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysis
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyResultsImportError

  @enum_values status: [:ok, :error]
  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    embeds_one :analysis, EvaluationAnalysis
    embeds_one :error, StudyResultsImportError
  end

  @type t :: %__MODULE__{
          status: String.t(),
          analysis: EvaluationAnalysis.t() | nil,
          error: StudyResultsImportError.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:analysis)
    |> cast_embed(:error)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "error"])
    |> validate_result()
  end

  defp validate_result(changeset) do
    case get_field(changeset, :status) do
      "ok" ->
        changeset
        |> validate_required([:analysis])
        |> validate_absent(:error)

      "error" ->
        changeset
        |> validate_required([:error])
        |> validate_absent(:analysis)

      _status ->
        changeset
    end
  end

  defp validate_absent(changeset, field) do
    if is_nil(get_field(changeset, field)) do
      changeset
    else
      add_error(changeset, field, "must be absent")
    end
  end
end
