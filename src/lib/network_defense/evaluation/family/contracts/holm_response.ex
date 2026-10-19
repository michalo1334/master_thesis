defmodule NetworkDefense.Evaluation.Family.Contracts.HolmResponse do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Family.Contracts.{
    AdjustedMember,
    FamilyError,
    HolmRequest,
    Identity
  }

  alias NetworkDefense.Evaluation.Family.SchemaValidator

  # Correction response. It must correlate exactly with the correction
  # request: no changed identity, changed raw p-value, missing row, extra row,
  # or inconsistent decision is accepted.

  @max_issues 50

  @type t :: %__MODULE__{
          schema_version: integer(),
          family_id: String.t(),
          method: String.t(),
          alpha: float(),
          family_size: integer(),
          results: [AdjustedMember.t()]
        }

  embedded_schema do
    field :schema_version, :integer
    field :family_id, :string
    field :method, :string
    field :alpha, :float
    field :family_size, :integer
    embeds_many :results, AdjustedMember, on_replace: :delete
  end

  def changeset(response, attrs) do
    response
    |> change()
    |> SchemaValidator.matches_schema(attrs, :holm_response)
    |> cast_if_schema_valid(attrs)
  end

  def parse(attrs, %HolmRequest{} = request) do
    changeset = changeset(%__MODULE__{}, attrs)

    case apply_action(changeset, :validate) do
      {:ok, response} ->
        with :ok <- validate_correlation(response, request), do: {:ok, response}

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           FamilyError.invalid_correction("The correction response could not be materialized.")
         )}
    end
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs),
    do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [:schema_version, :family_id, :method, :alpha, :family_size])
    |> cast_embed(:results, required: true)
  end

  defp validate_correlation(%__MODULE__{} = response, %HolmRequest{} = request) do
    expected = request.expected_comparisons
    family_size = length(expected)
    request_raw = Map.new(request.raw_results, fn raw -> {Identity.key(raw.identity), raw} end)

    issues =
      (metadata_issues(response, request, family_size) ++
         row_issues(response, expected, request_raw, request.alpha))
      |> Enum.take(@max_issues)

    case issues do
      [] -> :ok
      _issues -> {:error, FamilyError.invalid_correction_issues(issues)}
    end
  end

  defp metadata_issues(response, request, family_size) do
    [
      {"family_id", response.family_id, request.family_id},
      {"method", response.method, request.method},
      {"alpha", response.alpha, request.alpha},
      {"family_size", response.family_size, family_size},
      {"result_count", length(response.results), family_size}
    ]
    |> Enum.reject(fn {_field, actual, expected} -> actual == expected end)
    |> Enum.map(fn {field, actual, expected} ->
      %{
        "code" => "invalid_correction",
        "path" => [field],
        "message" => "The correction response does not match the correction request.",
        "details" => %{"expected" => expected, "actual" => actual}
      }
    end)
  end

  defp row_issues(response, expected, request_raw, alpha) do
    response.results
    |> Enum.zip(expected)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{row, identity}, index} ->
      identity_issues(row, identity, index) ++
        raw_value_issues(row, index, request_raw) ++ decision_issues(row, index, alpha)
    end)
  end

  defp identity_issues(row, expected_identity, index) do
    if Identity.matches?(row.identity, expected_identity) do
      []
    else
      [
        %{
          "code" => "invalid_correction",
          "path" => ["results", index, "identity"],
          "message" => "The correction response must keep the declared family order.",
          "details" => %{}
        }
      ]
    end
  end

  defp raw_value_issues(row, index, request_raw) do
    case Map.fetch(request_raw, Identity.key(row.identity)) do
      {:ok, %{raw_p_value: raw}} ->
        if raw == row.raw_p_value do
          []
        else
          [
            %{
              "code" => "invalid_correction",
              "path" => ["results", index, "raw_p_value"],
              "message" => "The correction response must not change a raw p-value.",
              "details" => %{}
            }
          ]
        end

      :error ->
        [
          %{
            "code" => "invalid_correction",
            "path" => ["results", index, "identity"],
            "message" => "The correction response contains an unexpected identity.",
            "details" => %{}
          }
        ]
    end
  end

  defp decision_issues(row, index, alpha) do
    if row.reject_null == row.adjusted_p_value <= alpha do
      []
    else
      [
        %{
          "code" => "invalid_correction",
          "path" => ["results", index, "reject_null"],
          "message" => "The correction decision must follow the adjusted p-value.",
          "details" => %{}
        }
      ]
    end
  end
end
