defmodule NetworkDefense.Evaluation2.Study.Definition.Inference do
  @moduledoc false

  use Spectral

  # One shared interval level. Pilot planning and Final reporting read the
  # same declaration, so no phase carries a second confidence setting.

  @type t :: %__MODULE__{confidence_level: float()}
  defstruct [:confidence_level]
end
