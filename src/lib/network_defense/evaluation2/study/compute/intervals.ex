defmodule NetworkDefense.Evaluation2.Study.Compute.Intervals do
  @moduledoc false

  alias NetworkDefense.Evaluation2.Study.Compute.Kernel

  @spec invert(map(), float()) :: {:ok, {float(), float()}} | :empty
  def invert(%{observations: observations, bets: bets}, error) do
    {lower, upper} =
      Nx.Defn.jit_apply(&Kernel.invert/3, [observations, bets, Nx.tensor(error, type: :f64)],
        compiler: EXLA,
        client: :host
      )

    lower = Nx.to_number(lower)
    upper = Nx.to_number(upper)
    if lower <= upper, do: {:ok, {lower, upper}}, else: :empty
  end
end
