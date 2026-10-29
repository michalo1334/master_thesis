defmodule NetworkDefense.Evaluation2.Study.Definition.Study do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Definition.Revisions

  @type t :: %__MODULE__{id: String.t(), revision: pos_integer(), revisions: Revisions.t()}
  defstruct [:id, :revision, :revisions]
end
