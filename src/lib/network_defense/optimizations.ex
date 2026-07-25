defmodule NetworkDefense.Optimizations do
  @moduledoc """
  Public context module for working with optimization related aspects
  """

  @optimization_events_topic "optimization_events"

  def optimization_events_topic, do: @optimization_events_topic

  def run_async(_request), do: {:error, :not_implemented}
end
