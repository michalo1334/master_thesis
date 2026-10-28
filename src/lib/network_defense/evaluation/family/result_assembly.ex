defmodule NetworkDefense.Evaluation.Family.ResultAssembly do
  @moduledoc false

  alias NetworkDefense.Evaluation.Family.Contracts.{Adjustment, ResultComparison}

  def adjusted_comparisons(members, adjustments) do
    members
    |> Enum.zip(adjustments)
    |> Enum.map(fn {member, adjusted} ->
      %ResultComparison{
        identity: member.identity,
        statistics: member.statistics,
        adjustment: %Adjustment{
          adjusted_p_value: adjusted.adjusted_p_value,
          reject_null: adjusted.reject_null
        }
      }
    end)
  end
end
