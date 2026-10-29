defmodule NetworkDefense.Evaluation2.NotImplementedError do
  @moduledoc false

  # Raised by an Evaluation2 scaffold function that has no behavior yet.
  #
  # The module tree, the typed contracts, and the public signatures exist so the
  # design can be reviewed before the collection, analysis, and lifecycle work is
  # written. Supported `Study` operations return bounded placeholder errors;
  # internal scaffold operations may raise this exception.
  #
  # A scaffold function raises after it accepted its declared arguments.

  defexception [:function]

  @type t :: %__MODULE__{function: atom() | nil}

  @impl Exception
  def message(%__MODULE__{function: function}) do
    "Evaluation2 function #{inspect(function)} is not implemented."
  end
end
