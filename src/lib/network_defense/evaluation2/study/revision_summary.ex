defmodule NetworkDefense.Evaluation2.Study.RevisionSummary do
  @moduledoc """
  Browse entry of one frozen revision.

  The value contains the optional display name, declared revision identity,
  creation time, stored execution count and most recently changed execution state.
  `latest_state` is nil when the revision has no execution, so an existing
  revision without executions stays distinguishable from a missing revision.

  SQL projects the name and scalar browse fields into compact application summaries.
  """

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Lifecycle
  alias NetworkDefense.Evaluation2.Study.Revision

  @type t :: %__MODULE__{
          revision: Revision.t(),
          name: String.t() | nil,
          created_at: DateTime.t(),
          execution_count: non_neg_integer(),
          latest_state: Lifecycle.state() | nil
        }

  defstruct [:revision, :name, :created_at, :execution_count, :latest_state]
end
