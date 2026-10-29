defmodule NetworkDefense.Evaluation2.NotImplementedError do
  @moduledoc """
  Raised by an Evaluation2 scaffold function that has no behavior yet.

  The module tree, the typed contracts, and the public signatures exist so the
  design can be reviewed before the collection, analysis, and lifecycle work is
  written. A scaffold function without a facade return value raises this exception
  after it accepted its declared arguments. The six public study operations return
  `{:error, :not_implemented}` instead.
  """

  defexception [:function]

  @type t :: %__MODULE__{function: atom()}

  @impl Exception
  def message(%__MODULE__{function: function}) do
    "Evaluation2 function #{inspect(function)} is not implemented."
  end
end
