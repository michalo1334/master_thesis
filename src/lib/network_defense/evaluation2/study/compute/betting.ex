defmodule NetworkDefense.Evaluation2.Study.Compute.Betting do
  @moduledoc """
  Fixed-sample, past-only bounded-mean betting on fixed matchings.

  Each matching has its own history. Arithmetic capital averages remain valid
  with dependent matchings. These averages are not an anytime-valid process.
  """

  alias NetworkDefense.Evaluation2.Study.Compute.Kernel

  @smallest_normal 2.2250738585072014e-308
  @log_smallest_normal :math.log(@smallest_normal)

  @doc "Calculate the sign-conservative two-sided p-value in log space."
  @spec p_value(map(), number()) :: float()
  def p_value(_prepared, estimate) when estimate == 0, do: 1.0

  def p_value(prepared, estimate), do: p_value_from_logs(log_capitals(prepared, 0.5), estimate)

  @doc false
  @spec p_value_from_logs({float(), float()}, number()) :: float()
  def p_value_from_logs(_capitals, estimate) when estimate == 0, do: 1.0

  def p_value_from_logs({plus, minus}, estimate) do
    selected = if estimate > 0, do: plus, else: minus
    log_p = min(0.0, :math.log(2.0) - selected)
    if log_p < @log_smallest_normal, do: @smallest_normal, else: :math.exp(log_p)
  end

  @doc "Prepare past-only base bets at the shared confidence error."
  @spec prepare(Nx.Tensor.t(), float()) :: %{observations: Nx.Tensor.t(), bets: Nx.Tensor.t()}
  def prepare(matchings, error) do
    {observations, bets} =
      Nx.Defn.jit_apply(&Kernel.prepare/2, [matchings, Nx.tensor(error, type: :f64)],
        compiler: EXLA,
        client: :host
      )

    %{observations: observations, bets: bets}
  end

  @doc "Return logs of the separate arithmetic positive and negative averages."
  @spec log_capitals(map(), float()) :: {float(), float()}
  def log_capitals(%{observations: xs, bets: bets}, mean) do
    {plus, minus} =
      Nx.Defn.jit_apply(&Kernel.log_capitals/3, [xs, bets, Nx.tensor(mean, type: :f64)],
        compiler: EXLA,
        client: :host
      )

    {Nx.to_number(plus), Nx.to_number(minus)}
  end
end
