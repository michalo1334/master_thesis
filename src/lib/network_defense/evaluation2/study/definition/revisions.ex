defmodule NetworkDefense.Evaluation2.Study.Definition.Revisions do
  @moduledoc false

  use Spectral

  # Declared revision assertions for the study environment and domain inputs.
  @type t :: %__MODULE__{
          model: String.t(),
          attacker: String.t(),
          defense: String.t(),
          rule: String.t(),
          strategy: String.t(),
          software: String.t(),
          application: String.t(),
          compute: String.t(),
          dependency: String.t(),
          environment: String.t()
        }
  defstruct [
    :model,
    :attacker,
    :defense,
    :rule,
    :strategy,
    :software,
    :application,
    :compute,
    :dependency,
    :environment
  ]
end
