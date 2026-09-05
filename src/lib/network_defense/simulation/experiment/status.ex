defmodule NetworkDefense.Simulation.Experiment.Status do
  @moduledoc false

  @values [:running, :failed, :completed, :cancelled]
  @wire_values Enum.map(@values, &Atom.to_string/1)

  @type t :: :running | :failed | :completed | :cancelled

  @spec values() :: [t()]
  def values, do: @values

  @spec wire_values() :: [String.t()]
  def wire_values, do: @wire_values

  defguard terminal?(status) when status in [:completed, :cancelled]

  defguard restartable?(status) when status == :failed

  @spec to_wire(t()) :: String.t()
  def to_wire(status), do: Atom.to_string(status)
end
