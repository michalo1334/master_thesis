defprotocol NetworkDefense.Rules.Rule do
  @moduledoc """
  Represents a condition that produces candidate actions (see `Action`) for simulator to perform
  """
  @spec evaluate(t(), NetworkDefense.Simulator.t()) :: list(NetworkDefense.Actions.Action.t())
  def evaluate(rule, simulation_state)
end
