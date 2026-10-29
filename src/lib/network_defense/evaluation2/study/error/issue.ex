defmodule NetworkDefense.Evaluation2.Study.Error.Issue do
  @moduledoc """
  One bounded diagnostic of a study error.

  A path names the rejected position inside the submitted document. The details
  map carries bounded extra facts. Parser output, submitted values, stack
  traces, and changesets stay internal.
  """

  use Spectral

  @typedoc "One path component: a field name or a list index."
  @type path_component :: String.t() | non_neg_integer()

  @typedoc "Path from the document root to one rejected position."
  @type path :: [path_component()]

  @type t :: %__MODULE__{
          code: String.t(),
          path: path(),
          message: String.t(),
          details: map()
        }

  defstruct [:code, :path, :message, :details]
end
