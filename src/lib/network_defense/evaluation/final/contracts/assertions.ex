defmodule NetworkDefense.Evaluation.Final.Contracts.Assertions do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # Caller assertions about Final evidence freshness and completion.
  #
  # These values are asserted, not authenticated and not physically proven.
  # The system rejects an assertion that contradicts itself, such as a claim
  # that the evidence is fresh but was not collected after the Pilot. The
  # system cannot show that collection occurred, that its time is true, or
  # that Pilot observations stayed outside the Final matrices.

  @type t :: %__MODULE__{
          final_evidence_collected_after_pilot: boolean(),
          pilot_observations_excluded: boolean(),
          collection_completed_at: String.t()
        }

  embedded_schema do
    field :final_evidence_collected_after_pilot, :boolean
    field :pilot_observations_excluded, :boolean
    field :collection_completed_at, :string
  end

  def changeset(assertions, attrs) do
    assertions
    |> cast(attrs, [
      :final_evidence_collected_after_pilot,
      :pilot_observations_excluded,
      :collection_completed_at
    ])
    |> validate_required([
      :final_evidence_collected_after_pilot,
      :pilot_observations_excluded,
      :collection_completed_at
    ])
  end

  @doc "Return the canonical assertion claim for a stored or submitted value."
  def claim(%__MODULE__{} = assertions) do
    %{
      "final_evidence_collected_after_pilot" => assertions.final_evidence_collected_after_pilot,
      "pilot_observations_excluded" => assertions.pilot_observations_excluded,
      "collection_completed_at" => assertions.collection_completed_at
    }
  end

  @doc "Check the claim booleans and the completion timestamp format."
  @spec issues(t()) :: [map()] | :ok
  def issues(%__MODULE__{} = assertions) do
    claim_issues =
      [
        {"final_evidence_collected_after_pilot", assertions.final_evidence_collected_after_pilot},
        {"pilot_observations_excluded", assertions.pilot_observations_excluded}
      ]
      |> Enum.reject(fn {_field, value} -> value == true end)
      |> Enum.map(fn {field, _value} ->
        %{
          "code" => "invalid_assertion",
          "path" => ["assertions", field],
          "message" => "The caller assertion is required and must be true.",
          "details" => %{}
        }
      end)

    case claim_issues ++ time_issues(assertions.collection_completed_at) do
      [] -> :ok
      issues -> issues
    end
  end

  defp time_issues(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} ->
        []

      _invalid ->
        [
          %{
            "code" => "invalid_assertion",
            "path" => ["assertions", "collection_completed_at"],
            "message" => "The asserted completion time must be an ISO 8601 timestamp.",
            "details" => %{}
          }
        ]
    end
  end
end
