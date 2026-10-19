defmodule NetworkDefense.Evaluation.Family.Contracts.FamilyRequest do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Family.Contracts.{ComparisonInput, FamilyError, Identity}
  alias NetworkDefense.Evaluation.Family.SchemaValidator
  alias NetworkDefense.Evaluation.JsonBoundary

  # Root family declaration. The declared expected family and the supplied
  # comparison inputs are separate lists, so missing and unexpected members
  # stay observable before any Gust run exists.

  @request_limit 1_048_576
  @max_issues 50

  @type t :: %__MODULE__{
          schema_version: integer(),
          evidence_role: String.t(),
          family_id: String.t(),
          method: String.t(),
          alpha: float(),
          expected_comparisons: [Identity.t()],
          comparisons: [ComparisonInput.t()]
        }

  embedded_schema do
    field :schema_version, :integer
    field :evidence_role, :string
    field :family_id, :string
    field :method, :string
    field :alpha, :float
    embeds_many :expected_comparisons, Identity, on_replace: :delete
    embeds_many :comparisons, ComparisonInput, on_replace: :delete
  end

  def changeset(request, attrs) do
    request
    |> change()
    |> SchemaValidator.matches_schema(attrs, :request)
    |> cast_if_schema_valid(attrs)
  end

  def parse(attrs) do
    with :ok <- string_keys_only(attrs),
         {:ok, encoded} <- encode(attrs),
         :ok <- within_limit(encoded),
         {:ok, request} <- materialize(attrs),
         :ok <- validate_nested_requests(attrs),
         :ok <- validate_family(request),
         {:ok, canonical_encoded} <- request |> to_params() |> encode(),
         :ok <- within_limit(canonical_encoded) do
      {:ok, request}
    end
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs),
    do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [:schema_version, :evidence_role, :family_id, :method, :alpha])
    |> cast_embed(:expected_comparisons, required: true)
    |> cast_embed(:comparisons, required: true)
  end

  defp materialize(attrs) when is_map(attrs) do
    changeset = changeset(%__MODULE__{}, attrs)

    case apply_action(changeset, :validate) do
      {:ok, request} ->
        {:ok, request}

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           FamilyError.workflow_failed("The validated family request could not be materialized.")
         )}
    end
  end

  defp materialize(_attrs), do: {:error, FamilyError.invalid_json_value([])}

  defp string_keys_only(attrs),
    do: JsonBoundary.string_keys_only(attrs, [], &FamilyError.invalid_json_value/1)

  defp encode(value), do: JsonBoundary.encode(value, &FamilyError.invalid_json_value/1)

  defp within_limit(encoded),
    do: JsonBoundary.within_limit(encoded, @request_limit, &FamilyError.request_too_large/1)

  defp validate_family(%__MODULE__{} = request) do
    issues =
      (duplicate_issues(
         request.expected_comparisons,
         ["expected_comparisons"],
         "duplicate_expected_identity",
         & &1
       ) ++
         duplicate_issues(
           request.comparisons,
           ["comparisons"],
           "duplicate_comparison_identity",
           & &1.identity
         ) ++
         set_issues(request) ++ agreement_issues(request.comparisons))
      |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
      |> Enum.take(@max_issues)

    case issues do
      [] -> :ok
      _issues -> {:error, FamilyError.validation_failed(issues)}
    end
  end

  # Every supplied comparison request must pass the accepted Stage 2 parser
  # before this family request can reach run creation. The parser receives the
  # supplied JSON, so it also rejects an unknown or missing nested field.
  #
  # This check runs only after the outer schema and cast succeeded. A malformed
  # identity therefore stops at the schema, and no nested diagnostic ever reads
  # or formats a submitted identity value.
  defp validate_nested_requests(%{"comparisons" => comparisons}) when is_list(comparisons) do
    issues =
      comparisons
      |> Enum.with_index()
      |> Enum.flat_map(fn {input, index} -> nested_issues(index, input) end)

    case issues do
      [] -> :ok
      _issues -> {:error, FamilyError.validation_failed(Enum.take(issues, @max_issues))}
    end
  end

  defp validate_nested_requests(_attrs), do: :ok

  defp nested_issues(index, %{"request" => request}),
    do: ComparisonInput.nested_issues(index, request)

  # A missing member field is a structural problem, so the schema reports it.
  defp nested_issues(_index, _input), do: []

  defp duplicate_issues(entries, path_prefix, code, identity_of) do
    {_seen, issues} =
      entries
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {entry, index}, {seen, issues} ->
        key = Identity.key(identity_of.(entry))

        if MapSet.member?(seen, key) do
          {seen,
           [issue(code, path_prefix ++ [index], duplicate_message(code), details(key)) | issues]}
        else
          {MapSet.put(seen, key), issues}
        end
      end)

    Enum.reverse(issues)
  end

  defp set_issues(%__MODULE__{} = request) do
    expected = request.expected_comparisons
    supplied = Enum.map(request.comparisons, & &1.identity)

    expected_keys = MapSet.new(expected, &Identity.key/1)
    supplied_keys = MapSet.new(supplied, &Identity.key/1)

    missing =
      expected
      |> Enum.with_index()
      |> Enum.reject(fn {identity, _index} ->
        MapSet.member?(supplied_keys, Identity.key(identity))
      end)
      |> Enum.map(fn {identity, index} ->
        issue(
          "missing_comparison",
          ["expected_comparisons", index],
          "Every expected identity must supply exactly one comparison.",
          details(Identity.key(identity))
        )
      end)

    unexpected =
      supplied
      |> Enum.with_index()
      |> Enum.reject(fn {identity, _index} ->
        MapSet.member?(expected_keys, Identity.key(identity))
      end)
      |> Enum.map(fn {identity, index} ->
        issue(
          "unexpected_comparison",
          ["comparisons", index, "identity"],
          "Every supplied comparison identity must be declared.",
          details(Identity.key(identity))
        )
      end)

    missing ++ unexpected
  end

  defp agreement_issues(comparisons) do
    comparisons
    |> Enum.with_index()
    |> Enum.flat_map(fn {%ComparisonInput{identity: identity, request: request}, index} ->
      [
        {"alternative", identity.alternative, request.evidence.alternative.strategy},
        {"reference", identity.reference, request.evidence.reference.strategy},
        {"outcome", identity.outcome, request.evidence.outcome}
      ]
      |> Enum.reject(fn {_field, declared, actual} -> declared == actual end)
      |> Enum.map(fn {field, declared, actual} ->
        issue(
          "identity_mismatch",
          ["comparisons", index, "identity", field],
          "The identity field must agree with the comparison request.",
          %{"declared" => declared, "request" => actual}
        )
      end)
    end)
  end

  defp issue(code, path, message, details) do
    %{"code" => code, "path" => path, "message" => message, "details" => details}
  end

  defp duplicate_message("duplicate_expected_identity"),
    do: "Expected comparison identities must be unique."

  defp duplicate_message("duplicate_comparison_identity"),
    do: "Supplied comparison identities must be unique."

  defp details({tier, budget, alternative, reference, outcome}) do
    %{
      "tier" => tier,
      "budget" => budget,
      "alternative" => alternative,
      "reference" => reference,
      "outcome" => outcome
    }
  end

  defp path_sort_key(path) do
    Enum.map(path, fn
      value when is_binary(value) -> {0, value}
      value when is_integer(value) -> {1, value}
    end)
  end
end
