defmodule NetworkDefense.Evaluation2.NotImplementedError do
  @moduledoc false

  # Historical scaffold exception retained until the verification/deletion gate.
  # It is outside the implemented Study facade and its native lifecycle path.

  defexception [:function]

  @type t :: %__MODULE__{function: atom() | nil}

  @impl Exception
  def message(%__MODULE__{function: function}) do
    "Evaluation2 function #{inspect(function)} is not implemented."
  end
end
