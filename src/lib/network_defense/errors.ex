defmodule NetworkDefense.Errors do
  @moduledoc false

  alias NetworkDefense.Graph.Errors, as: GraphErrors
  alias NetworkDefense.Optimizations.Errors, as: OptimizationErrors
  alias NetworkDefense.Simulations.Errors, as: SimulationErrors

  @codes Enum.uniq(
           GraphErrors.codes() ++
             SimulationErrors.codes() ++ OptimizationErrors.codes() ++ [:invalid_request]
         )

  @type code ::
          GraphErrors.code()
          | SimulationErrors.code()
          | OptimizationErrors.code()
          | :invalid_request

  @spec codes() :: [code()]
  def codes, do: @codes

  @spec strings() :: [String.t()]
  def strings, do: Enum.map(@codes, &Atom.to_string/1)

  @spec to_wire(term()) :: String.t()
  def to_wire(code) when code in @codes, do: Atom.to_string(code)
  def to_wire(_code), do: "internal_error"
end
