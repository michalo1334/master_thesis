defmodule NetworkDefense.Evaluation.Study.PilotOutcome do
  @moduledoc false

  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotResult, Recommendation}
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  @enforce_keys [:outcome]
  defstruct [:outcome, :candidate_id, :plan_count_per_side, :attacks_per_plan, :reason]

  @type t :: %__MODULE__{
          outcome: :recommended | :insufficient,
          candidate_id: String.t() | nil,
          plan_count_per_side: pos_integer() | nil,
          attacks_per_plan: pos_integer() | nil,
          reason: String.t() | nil
        }

  @spec from_result(PilotResult.t()) :: {:ok, t()} | {:error, StudyError.t()}
  def from_result(%PilotResult{
        outcome: "recommended",
        recommendation: %Recommendation{} = recommendation
      }) do
    parse(%{
      "outcome" => "recommended",
      "candidate_id" => recommendation.candidate_id,
      "plan_count_per_side" => recommendation.plan_count,
      "attacks_per_plan" => recommendation.attacks_per_plan
    })
  end

  def from_result(%PilotResult{
        outcome: "insufficient",
        recommendation: nil,
        insufficient_reason: reason
      }) do
    parse(%{"outcome" => "insufficient", "reason" => reason})
  end

  def from_result(_result), do: {:error, StudyError.pilot_outcome_invalid()}

  @spec parse(term()) :: {:ok, t()} | {:error, StudyError.t()}
  def parse(
        %{
          "outcome" => "recommended",
          "candidate_id" => candidate_id,
          "plan_count_per_side" => plan_count,
          "attacks_per_plan" => attacks
        } = attrs
      )
      when map_size(attrs) == 4 and is_binary(candidate_id) and byte_size(candidate_id) in 1..128 and
             is_integer(plan_count) and plan_count > 0 and is_integer(attacks) and attacks > 0 do
    {:ok,
     %__MODULE__{
       outcome: :recommended,
       candidate_id: candidate_id,
       plan_count_per_side: plan_count,
       attacks_per_plan: attacks
     }}
  end

  def parse(%{"outcome" => "insufficient", "reason" => reason} = attrs)
      when map_size(attrs) == 2 and is_binary(reason) and byte_size(reason) in 1..128 do
    {:ok, %__MODULE__{outcome: :insufficient, reason: reason}}
  end

  def parse(_attrs), do: {:error, StudyError.pilot_outcome_invalid()}

  @spec to_params(t()) :: map()
  def to_params(%__MODULE__{outcome: :recommended} = outcome) do
    %{
      "outcome" => "recommended",
      "candidate_id" => outcome.candidate_id,
      "plan_count_per_side" => outcome.plan_count_per_side,
      "attacks_per_plan" => outcome.attacks_per_plan
    }
  end

  def to_params(%__MODULE__{outcome: :insufficient, reason: reason}) do
    %{"outcome" => "insufficient", "reason" => reason}
  end
end
