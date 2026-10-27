defmodule NetworkDefense.DocumentCatalog.Kind do
  @moduledoc false

  @kinds [
    graph: "Graph",
    simulation_report: "Simulation report",
    optimization_report: "Optimization report"
  ]
  @labels Map.new(@kinds)

  @spec values() :: [atom()]
  def values, do: Keyword.keys(@kinds)

  @spec strings() :: [String.t()]
  def strings, do: Enum.map(values(), &value/1)

  @spec value(atom()) :: String.t()
  def value(kind), do: Atom.to_string(kind)

  @spec label(atom()) :: String.t()
  def label(kind), do: Map.fetch!(@labels, kind)
end
