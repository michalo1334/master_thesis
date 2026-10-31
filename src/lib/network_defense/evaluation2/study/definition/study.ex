defmodule NetworkDefense.Evaluation2.Study.Definition.Study do
  @moduledoc false

  use Spectral

  # Operator-declared study identity. The revision number is the durable
  # identity of one frozen definition, so it is declared here and never
  # asserted from runtime metadata.

  @type t :: %__MODULE__{id: String.t(), revision: pos_integer()}
  defstruct [:id, :revision]
end
