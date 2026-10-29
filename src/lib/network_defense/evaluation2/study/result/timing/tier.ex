defmodule NetworkDefense.Evaluation2.Study.Result.Timing.Tier do
  @moduledoc """
  Measured replicas of one network-size tier.

  Positions zero through four identify the measured replicas.
  """

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Result.Timing.Replica

  @typedoc "The five measured replicas of one tier, keyed by measured position."
  @type replicas :: %{
          required(0) => Replica.t(),
          required(1) => Replica.t(),
          required(2) => Replica.t(),
          required(3) => Replica.t(),
          required(4) => Replica.t()
        }

  @type t :: %__MODULE__{replicas: replicas()}

  defstruct [:replicas]
end
