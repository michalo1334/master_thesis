defmodule NetworkDefense.Evaluation2.Study.Error do
  @moduledoc """
  Bounded error of the supported study boundary.

  Four categories cover every public failure. One typed issue list carries the
  bounded diagnostics, so schema diagnostics and other internal diagnostics share
  one shape. Internal failures map into this type once.

  The value appears in facade error tuples and in the `failed` variant of
  `NetworkDefense.Evaluation2.Study.Status`.
  """

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Error.Issue

  @typedoc "Outer failure category of one study operation."
  @type category :: :validation_failed | :request_too_large | :conflict | :unavailable

  @type t :: %__MODULE__{
          category: category(),
          issues: [Issue.t()]
        }

  defstruct [:category, :issues]
end
