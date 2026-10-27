defmodule NetworkDefense.Evaluation.Study.CompactResult do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Contracts
  alias NetworkDefense.Evaluation.Final.Contracts.Result, as: FinalResult
  alias NetworkDefense.Evaluation.Study.CompactResult.{AnalysisReference, CollectionReference}
  alias NetworkDefense.Evaluation.Study.CompactResult.PilotAnalysisReference
  alias NetworkDefense.Evaluation.Study.Contracts.Definition.Revisions
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.{FinalSelection, PilotOutcome}
  alias NetworkDefense.Evaluation.Study.Timing.TimingSummary

  @primary_key false
  embedded_schema do
    field :study_revision_id, :binary_id
    field :execution_id, :binary_id
    embeds_one :pilot_collection, CollectionReference
    embeds_one :pilot_analysis, PilotAnalysisReference
    embeds_one :selection, FinalSelection
    embeds_one :final_collection, CollectionReference
    embeds_one :final_analysis, AnalysisReference
    embeds_one :final_result, FinalResult
    embeds_one :revision_assertions, Revisions
    embeds_one :timing, TimingSummary, on_replace: :update
  end

  @type t :: %__MODULE__{
          study_revision_id: Ecto.UUID.t(),
          execution_id: Ecto.UUID.t(),
          pilot_collection: CollectionReference.t(),
          pilot_analysis: PilotAnalysisReference.t(),
          selection: FinalSelection.t(),
          final_collection: CollectionReference.t(),
          final_analysis: AnalysisReference.t(),
          final_result: FinalResult.t(),
          revision_assertions: Revisions.t(),
          timing: TimingSummary.t() | nil
        }

  @spec parse(term()) :: {:ok, t()} | {:error, StudyError.t()}
  def parse(attrs) when is_map(attrs) do
    with true <- exact_fields?(attrs, __MODULE__),
         {:ok, result} <- apply_action(changeset(%__MODULE__{}, attrs), :validate),
         :ok <- FinalResult.validate_intrinsic(result.final_result) do
      {:ok, result}
    else
      _invalid -> {:error, StudyError.final_result_invalid()}
    end
  end

  def parse(_attrs), do: {:error, StudyError.final_result_invalid()}

  defp changeset(result, attrs) do
    result
    |> cast(attrs, [:study_revision_id, :execution_id], empty_values: [])
    |> validate_required([:study_revision_id, :execution_id])
    |> cast_embed(:pilot_collection, required: true)
    |> cast_embed(:pilot_analysis, required: true)
    |> cast_embed(:selection, required: true)
    |> cast_embed(:final_collection, required: true)
    |> cast_embed(:final_analysis, required: true)
    |> cast_embed(:final_result, required: true)
    |> cast_embed(:revision_assertions, required: true)
    |> cast_embed(:timing, required: false)
  end

  @spec to_params(t()) :: map()
  def to_params(%__MODULE__{} = result) do
    result
    |> Contracts.to_params()
    |> put_in(
      ["pilot_analysis", "outcome"],
      PilotOutcome.to_params(result.pilot_analysis.outcome)
    )
  end

  # Ecto casts ignore unknown keys. Check the JSON shape against the embedded
  # fields before casting, without maintaining a second list of payload keys.
  # FinalResult has its own strict JSON schema; PilotOutcome has its own parser.
  #
  # This check owns unknown-field rejection for every level, so the embedded
  # changesets keep value validation only. A nil optional embed passes here and
  # stays rejected by its own `cast_embed(required: true)` where it is required.
  defp exact_fields?(_attrs, FinalResult), do: true

  defp exact_fields?(nil, _schema), do: true

  defp exact_fields?(attrs, schema) when is_map(attrs) do
    fields = schema.__schema__(:fields) ++ schema.__schema__(:virtual_fields)
    expected = Enum.map(fields, &Atom.to_string/1)

    Enum.sort(Map.keys(attrs)) == Enum.sort(expected) and
      Enum.all?(schema.__schema__(:embeds), fn field ->
        embed = schema.__schema__(:embed, field)
        exact_embed?(attrs[Atom.to_string(field)], embed)
      end)
  end

  defp exact_fields?(_attrs, _schema), do: false

  defp exact_embed?(nil, _embed), do: true

  defp exact_embed?(items, %{cardinality: :many} = embed) when is_list(items) do
    Enum.all?(items, &exact_fields?(&1, embed.related))
  end

  defp exact_embed?(item, %{cardinality: :one} = embed) when is_map(item) do
    exact_fields?(item, embed.related)
  end

  defp exact_embed?(_other, _embed), do: false
end
