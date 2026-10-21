defmodule NetworkDefense.Evaluation.Final.Contracts.SnapshotPayload do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Final.Contracts.{ComparisonEvidence, FinalError}
  alias NetworkDefense.Evaluation.Final.SchemaValidator
  alias NetworkDefense.Evaluation.JsonBoundary

  # Stored Final evidence payload.
  #
  # Database columns own the study revision, phase, schema version, and family
  # ID, so the payload never repeats them. The payload holds the crossed
  # evidence matrices and caller-asserted provenance. Analysis settings and
  # Final seeds stay in the submitted Final request; they are not evidence.
  #
  # Cross-field validation keeps the declared order authoritative: positions
  # are consecutive from zero, identities are unique, and each identity agrees
  # with its evidence matrix.

  @max_issues 50

  @type t :: %__MODULE__{
          schema_version: integer(),
          evidence_role: String.t(),
          comparisons: [ComparisonEvidence.t()]
        }

  embedded_schema do
    field :schema_version, :integer
    field :evidence_role, :string
    embeds_many :comparisons, ComparisonEvidence, on_replace: :delete
  end

  def changeset(payload, attrs) do
    payload
    |> change()
    |> SchemaValidator.matches_schema(attrs, :snapshot_payload)
    |> cast_if_schema_valid(attrs)
  end

  @spec parse(term()) :: {:ok, t()} | {:error, FinalError.t()}
  def parse(attrs) do
    with :ok <- string_keys_only(attrs),
         {:ok, payload} <- materialize(attrs) do
      build(payload)
    end
  end

  @spec build(t()) :: {:ok, t()} | {:error, FinalError.t()}
  def build(%__MODULE__{} = payload), do: validate_payload(payload)
  def build(_value), do: {:error, FinalError.invalid_json_value(["payload"])}

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs), do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [:schema_version, :evidence_role])
    |> cast_embed(:comparisons, required: true)
  end

  defp materialize(attrs) when is_map(attrs) do
    changeset = changeset(%__MODULE__{}, attrs)

    case apply_action(changeset, :validate) do
      {:ok, payload} ->
        {:ok, payload}

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           FinalError.changed_snapshot("The Final snapshot payload could not be materialized.")
         )}
    end
  end

  defp materialize(_attrs), do: {:error, FinalError.invalid_json_value(["payload"])}

  defp string_keys_only(attrs) do
    JsonBoundary.string_keys_only(attrs, [], &FinalError.invalid_json_value/1)
  end

  defp validate_payload(%__MODULE__{} = payload) do
    issues =
      payload.comparisons
      |> Enum.with_index()
      |> Enum.flat_map(fn {comparison, index} -> comparison_issues(comparison, index) end)
      |> Kernel.++(duplicate_comparison_issues(payload.comparisons))
      |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
      |> Enum.take(@max_issues)

    case issues do
      [] -> {:ok, payload}
      _issues -> {:error, FinalError.validation_failed(issues)}
    end
  end

  defp comparison_issues(%ComparisonEvidence{} = comparison, index) do
    position_issues(comparison, index) ++ evidence_issues(comparison, index)
  end

  defp position_issues(%ComparisonEvidence{position: position}, index) do
    if position == index do
      []
    else
      [
        issue(
          "non_consecutive_position",
          ["comparisons", index, "position"],
          "Comparison positions must be consecutive from zero.",
          %{"declared" => position, "expected" => index}
        )
      ]
    end
  end

  defp evidence_issues(%ComparisonEvidence{} = comparison, index) do
    identity = comparison.identity
    evidence = comparison.evidence

    attack_count = length(evidence.attack_seeds)

    agreement_issues(identity, evidence, index) ++
      alternative_strategy_issues(identity, index) ++
      side_issues(
        evidence.alternative,
        ["comparisons", index, "evidence", "alternative"],
        attack_count
      ) ++
      side_issues(
        evidence.reference,
        ["comparisons", index, "evidence", "reference"],
        attack_count
      )
  end

  defp agreement_issues(identity, evidence, index) do
    [
      {"alternative", identity.alternative, evidence.alternative.strategy},
      {"reference", identity.reference, evidence.reference.strategy},
      {"outcome", identity.outcome, evidence.outcome}
    ]
    |> Enum.reject(fn {_field, declared, actual} -> declared == actual end)
    |> Enum.map(fn {field, declared, actual} ->
      issue(
        "identity_mismatch",
        ["comparisons", index, "identity", field],
        "The identity field must agree with the comparison evidence.",
        %{"declared" => declared, "request" => actual}
      )
    end)
  end

  defp alternative_strategy_issues(%Identity{alternative: "cvss"}, index) do
    [
      issue(
        "unsupported_alternative_strategy",
        ["comparisons", index, "identity", "alternative"],
        "The alternative strategy must not be the reference strategy.",
        %{"alternative" => "cvss"}
      )
    ]
  end

  defp alternative_strategy_issues(_identity, _index), do: []

  defp side_issues(side, path, attack_count) do
    duplicate_plan_issues(side.plans, path) ++ column_issues(side.plans, attack_count, path)
  end

  defp duplicate_plan_issues(plans, path) do
    {_seen, issues} =
      plans
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {plan, index}, {seen, issues} ->
        if MapSet.member?(seen, plan.id) do
          {seen,
           [
             issue(
               "duplicate_plan_id",
               path ++ ["plans", index, "id"],
               "Plan IDs must be unique inside one side.",
               %{"plan_id" => plan.id}
             )
             | issues
           ]}
        else
          {MapSet.put(seen, plan.id), issues}
        end
      end)

    Enum.reverse(issues)
  end

  defp column_issues(plans, attack_count, path) do
    plans
    |> Enum.with_index()
    |> Enum.reject(fn {plan, _index} -> length(plan.mission_impacts) == attack_count end)
    |> Enum.map(fn {plan, index} ->
      issue(
        "attack_column_count_mismatch",
        path ++ ["plans", index, "mission_impacts"],
        "Every plan must repeat the attack seed count.",
        %{"expected" => attack_count, "actual" => length(plan.mission_impacts)}
      )
    end)
  end

  defp duplicate_comparison_issues(comparisons) do
    {_seen, issues} =
      comparisons
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {comparison, index}, {seen, issues} ->
        key = Identity.key(comparison.identity)

        if MapSet.member?(seen, key) do
          {seen,
           [
             issue(
               "duplicate_comparison",
               ["comparisons", index, "identity"],
               "Comparison identities must be unique.",
               identity_details(key)
             )
             | issues
           ]}
        else
          {MapSet.put(seen, key), issues}
        end
      end)

    Enum.reverse(issues)
  end

  defp identity_details({tier, budget, alternative, reference, outcome}) do
    %{
      "tier" => tier,
      "budget" => budget,
      "alternative" => alternative,
      "reference" => reference,
      "outcome" => outcome
    }
  end

  defp issue(code, path, message, details) do
    %{"code" => code, "path" => path, "message" => message, "details" => details}
  end

  defp path_sort_key(path) do
    Enum.map(path, fn
      value when is_binary(value) -> {0, value}
      value when is_integer(value) -> {1, value}
    end)
  end
end
