defprotocol NetworkDefense.Rules.Rule do
  @moduledoc """
  Represents a condition that produces candidate actions (see `Action`) for simulator to perform
  """
  alias NetworkDefense.Simulator
  @spec evaluate(t(), Simulator) :: list(Action.t())
  def evaluate(rule, simulation_state)
end
