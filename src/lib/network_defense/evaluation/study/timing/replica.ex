defmodule NetworkDefense.Evaluation.Study.Timing.Replica do
  @moduledoc false

  @enforce_keys [:tier, :position, :kind]
  defstruct [:tier, :position, :kind]

  @type kind :: :warm_up | :measured
  @type position :: -1 | 0..4

  @type t :: %__MODULE__{
          tier: String.t(),
          position: position(),
          kind: kind()
        }
end
