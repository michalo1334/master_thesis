defmodule NetworkDefense.Evaluation.Family.Contracts.ComparisonInput do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonError, ComparisonRequest}
  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  # One supplied family member: its identity and its existing comparison
  # request. The nested comparison contract owns the request shape.

  @type t :: %__MODULE__{identity: Identity.t(), request: ComparisonRequest.t()}

  embedded_schema do
    embeds_one :identity, Identity, on_replace: :update
    embeds_one :request, ComparisonRequest, on_replace: :update
  end

  def changeset(input, attrs) do
    input
    |> cast(attrs, [])
    |> cast_embed(:identity, required: true)
    |> cast_embed(:request, required: true)
  end

  # The accepted Stage 2 comparison parser owns every rule for a nested
  # request: strict types, unknown fields, counts, duplicate identifiers, and
  # cross-evidence agreement. The family must run that parser on the supplied
  # request itself and must not repeat its rules.
  #
  # Validation runs on the supplied JSON, not on the cast struct, so a lost
  # field or an ignored unknown field cannot hide from the parser.
  #
  # The returned issues keep the nested code and add the member path, so a
  # caller can see which member failed and where.
  #
  # The diagnostics never read, format, or copy the supplied identity. The
  # member index and the request path identify the member. A caller must not
  # serialize an unvalidated identity value into an error.
  @spec nested_issues(integer(), term()) :: [map()]
  def nested_issues(index, request) do
    case ComparisonRequest.parse(request) do
      {:ok, %ComparisonRequest{}} ->
        []

      {:error, %ComparisonError{} = error} ->
        prefixed_issues(index, error)

      {:error, _other} ->
        [summary_issue(index, "The nested comparison request is invalid.")]
    end
  end

  defp prefixed_issues(index, %ComparisonError{issues: [_ | _] = issues}) do
    Enum.map(issues, fn issue ->
      %{
        "code" => issue["code"],
        "path" => ["comparisons", index, "request" | List.wrap(issue["path"])],
        "message" => issue["message"],
        "details" => member_details(issue["details"], index)
      }
    end)
  end

  defp prefixed_issues(index, %ComparisonError{} = error) do
    case error.schema_errors do
      [] ->
        [summary_issue(index, "The nested comparison request is invalid.")]

      diagnostics ->
        diagnostics
        |> Enum.take(10)
        |> Enum.map(fn diagnostic ->
          %{
            "code" => "invalid_comparison_request",
            "path" => [
              "comparisons",
              index,
              "request" | diagnostic_path(Map.get(diagnostic, "path"))
            ],
            "message" => Map.get(diagnostic, "message", "The nested contract is invalid."),
            "details" => member_details(nil, index)
          }
        end)
    end
  end

  defp summary_issue(index, message) do
    %{
      "code" => "invalid_comparison_request",
      "path" => ["comparisons", index, "request"],
      "message" => message,
      "details" => member_details(nil, index)
    }
  end

  defp diagnostic_path(path) when is_list(path), do: path
  defp diagnostic_path(_path), do: []

  # Detail values stay scalar, because the bounded error schema allows scalar
  # values and short scalar lists only.
  defp member_details(details, index) do
    details
    |> case do
      map when is_map(map) -> map
      _other -> %{}
    end
    |> Map.take(["expected", "actual", "first_index"])
    |> Map.put("member_index", index)
  end
end
