defmodule NetworkDefense.DocumentCatalog.KindTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.DocumentCatalog.Kind

  @ordered_strings [
    "graph",
    "simulation_report",
    "optimization_report"
  ]

  test "CATALOG-KIND-01: returns stable public kind and wire-string order" do
    assert Enum.map(Kind.values(), &Atom.to_string/1) == @ordered_strings
    assert Kind.strings() == @ordered_strings
  end

  test "CATALOG-KIND-02: preserves values, labels, and unknown-label errors" do
    assert Enum.map(Kind.values(), &Kind.value/1) == @ordered_strings
    assert Kind.value(:unknown) == "unknown"

    assert Enum.map(Kind.values(), &Kind.label/1) == [
             "Graph",
             "Simulation report",
             "Optimization report"
           ]

    assert_raise KeyError, fn -> Kind.label(:unknown) end
  end
end
