defmodule NetworkDefense.Analysis.Errors do
  @moduledoc false

  @codes [:invalid_analysis, :invalid_analyses]

  @type code :: :invalid_analysis | :invalid_analyses

  @spec codes() :: [code()]
  def codes, do: @codes
end
