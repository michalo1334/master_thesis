defmodule NetworkDefense.Evaluation2.Study.Definition.Study do
  @moduledoc false

  use Spectral

  # The optional display name leaves revision identity and scientific seeds unchanged.
  @type t :: %__MODULE__{id: String.t(), revision: pos_integer(), name: String.t() | nil}
  defstruct [:id, :revision, :name]
end
