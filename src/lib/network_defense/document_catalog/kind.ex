defmodule NetworkDefense.DocumentCatalog.Kind do
  @moduledoc false

  @labels %{
    graph: "Graph",
    simulation_report: "Simulation report",
    optimization_report: "Optimization report"
  }

  @spec values() :: [atom()]
  def values, do: Map.keys(@labels)

  @spec strings() :: [String.t()]
  def strings, do: Enum.map(values(), &value/1)

  @spec value(atom()) :: String.t()
  def value(kind), do: Atom.to_string(kind)

  @spec label(atom()) :: String.t()
  def label(kind), do: Map.fetch!(@labels, kind)
end
