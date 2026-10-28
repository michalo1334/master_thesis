defmodule NetworkDefense.Evaluation.Study.WaitDeadline do
  @moduledoc false

  @type t :: integer() | :infinity

  @spec new(timeout()) :: t()
  def new(:infinity), do: :infinity
  def new(timeout), do: System.monotonic_time(:millisecond) + timeout

  @spec remaining(t()) :: timeout()
  def remaining(:infinity), do: :infinity
  def remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
