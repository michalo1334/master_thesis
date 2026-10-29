defmodule NetworkDefense.Evaluation2.Study.Definition.PilotToFinal do
  @moduledoc false

  use Spectral

  # The declared handoff mode is pause for explicit approval.
  @type t :: %__MODULE__{mode: String.t()}
  defstruct [:mode]
end
