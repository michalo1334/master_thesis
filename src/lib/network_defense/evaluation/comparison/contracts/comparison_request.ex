defmodule NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{
    ComparisonError,
    Evidence,
    IntervalSpec,
    ResamplingSpec,
    TestSpec
  }

  alias NetworkDefense.Evaluation.Comparison.SchemaValidator
  alias NetworkDefense.Evaluation.JsonBoundary

  @request_limit 1_048_576

  @type t :: %__MODULE__{}

  embedded_schema do
    field :schema_version, :integer
    embeds_one :evidence, Evidence, on_replace: :update
    embeds_one :resampling, ResamplingSpec, on_replace: :update
    embeds_one :interval, IntervalSpec, on_replace: :update
    embeds_one :test, TestSpec, on_replace: :update
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
         :ok <- validate_crossed_evidence(request),
         {:ok, canonical_encoded} <- request |> to_params() |> encode(),
         :ok <- within_limit(canonical_encoded) do
      {:ok, request}
    end
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs),
    do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [:schema_version])
    |> cast_embed(:evidence, required: true)
    |> cast_embed(:resampling, required: true)
    |> cast_embed(:interval, required: true)
    |> cast_embed(:test, required: true)
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
           ComparisonError.workflow_failed("The validated request could not be materialized.")
         )}
    end
  end

  defp materialize(_attrs), do: {:error, ComparisonError.invalid_json_value([])}

  defp string_keys_only(attrs),
    do: JsonBoundary.string_keys_only(attrs, [], &ComparisonError.invalid_json_value/1)

  defp encode(value), do: JsonBoundary.encode(value, &ComparisonError.invalid_json_value/1)

  defp within_limit(encoded),
    do: JsonBoundary.within_limit(encoded, @request_limit, &ComparisonError.request_too_large/1)

  defp validate_crossed_evidence(request) do
    expected = length(request.evidence.attack_seeds)

    issues =
      [
        side_issues("alternative", request.evidence.alternative.plans, expected),
        side_issues("reference", request.evidence.reference.plans, expected)
      ]
      |> List.flatten()
      |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
      |> Enum.take(50)

    case issues do
      [] -> :ok
      _issues -> {:error, %ComparisonError{code: "validation_failed", issues: issues}}
    end
  end

  defp side_issues(side_name, plans, expected) do
    {_seen, issues} =
      plans
      |> Enum.with_index()
      |> Enum.reduce({%{}, []}, fn {plan, index}, {seen, issues} ->
        {seen, issues} = duplicate_issue(plan, side_name, index, seen, issues)
        issues = alignment_issue(plan, side_name, index, expected, issues)
        {seen, issues}
      end)

    Enum.reverse(issues)
  end

  defp duplicate_issue(plan, side_name, index, seen, issues) do
    case Map.fetch(seen, plan.id) do
      {:ok, first_index} ->
        issue = %{
          "code" => "duplicate_plan_id",
          "path" => ["evidence", side_name, "plans", index, "id"],
          "message" => "Plan IDs must be unique within each comparison side.",
          "details" => %{"first_index" => first_index}
        }

        {seen, [issue | issues]}

      :error ->
        {Map.put(seen, plan.id, index), issues}
    end
  end

  defp alignment_issue(plan, side_name, index, expected, issues) do
    actual = length(plan.mission_impacts)

    if actual == expected do
      issues
    else
      [
        %{
          "code" => "attack_column_count_mismatch",
          "path" => ["evidence", side_name, "plans", index, "mission_impacts"],
          "message" => "Expected #{expected} mission-impact values but received #{actual}.",
          "details" => %{"expected" => expected, "actual" => actual}
        }
        | issues
      ]
    end
  end

  defp path_sort_key(path) do
    Enum.map(path, fn
      value when is_binary(value) -> {0, value}
      value when is_integer(value) -> {1, value}
    end)
  end
end
