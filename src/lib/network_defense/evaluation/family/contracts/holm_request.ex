defmodule NetworkDefense.Evaluation.Family.Contracts.HolmRequest do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyError, Identity, RawResult}
  alias NetworkDefense.Evaluation.Family.SchemaValidator

  # Small correction request. It contains identities and raw p-values only.
  # Evidence matrices stay in the persisted comparison results.

  @type t :: %__MODULE__{
          schema_version: integer(),
          family_id: String.t(),
          method: String.t(),
          alpha: float(),
          expected_comparisons: [Identity.t()],
          raw_results: [RawResult.t()]
        }

  embedded_schema do
    field :schema_version, :integer
    field :family_id, :string
    field :method, :string
    field :alpha, :float
    embeds_many :expected_comparisons, Identity, on_replace: :delete
    embeds_many :raw_results, RawResult, on_replace: :delete
  end

  def changeset(request, attrs) do
    request
    |> change()
    |> SchemaValidator.matches_schema(attrs, :holm_request)
    |> cast_if_schema_valid(attrs)
  end

  def parse(attrs) do
    case apply_action(changeset(%__MODULE__{}, attrs), :validate) do
      {:ok, request} ->
        {:ok, request}

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(changeset, FamilyError.invalid_correction())}
    end
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs),
    do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [:schema_version, :family_id, :method, :alpha])
    |> cast_embed(:expected_comparisons, required: true)
    |> cast_embed(:raw_results, required: true)
  end
end
