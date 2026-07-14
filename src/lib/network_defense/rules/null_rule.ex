defmodule NetworkDefense.Rules.NullRule do
  alias NetworkDefense.Rules.Rule

  @moduledoc """
  A rule that returns no candidate actions.
  """
  defstruct []

  defimpl Rule, for: __MODULE__ do
    def evaluate(_rule, _simulation_state), do: []
  end
end
