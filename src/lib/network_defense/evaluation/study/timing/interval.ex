defmodule NetworkDefense.Evaluation.Study.Timing.Interval do
  @moduledoc false

  @enforce_keys [:elapsed_us]
  defstruct [:elapsed_us]

  @type t :: %__MODULE__{elapsed_us: non_neg_integer()}

  @spec between(started_us :: integer(), finished_us :: integer()) ::
          {:ok, t()} | {:error, :invalid_interval}
  def between(started_us, finished_us) when finished_us >= started_us do
    {:ok, %__MODULE__{elapsed_us: finished_us - started_us}}
  end

  def between(_started_us, _finished_us), do: {:error, :invalid_interval}
end
