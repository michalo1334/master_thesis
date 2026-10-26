defmodule NetworkDefense.Evaluation.Study.Timing do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Timing.Replica

  @spec schedule([String.t()]) :: [Replica.t()]
  def schedule(tiers), do: Enum.flat_map(tiers, &schedule_tier/1)

  defp schedule_tier(tier) do
    [
      %Replica{tier: tier, position: -1, kind: :warm_up}
      | Enum.map(0..4, &%Replica{tier: tier, position: &1, kind: :measured})
    ]
  end
end
