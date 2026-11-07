defmodule NetworkDefense.Evaluation2.Study.RevisionSummary do
  @moduledoc """
  Browse entry of one frozen revision.

  The value names the declared revision identity, the creation time, the number
  of stored executions and the state of the most recently changed execution.
  `latest_state` is nil when the revision has no execution, so an existing
  revision without executions stays distinguishable from a missing revision.

  The entry holds no definition, report or collection matrix, so listing
  revisions never reads stored scientific payloads.
  """

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Lifecycle
  alias NetworkDefense.Evaluation2.Study.Revision

  @type t :: %__MODULE__{
          revision: Revision.t(),
          created_at: DateTime.t(),
          execution_count: non_neg_integer(),
          latest_state: Lifecycle.state() | nil
        }

  defstruct [:revision, :created_at, :execution_count, :latest_state]
end
