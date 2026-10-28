defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.TimingSummary
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}

  # The accepted handoff from Final collection to Final analysis.
  #
  # Collection returns this value after the successful transition. It carries the
  # accepted identity of the collection result, so analysis never reads the
  # collection phase to rebuild it.
  #
  # `request`, `gust_run`, and `result` are the later analysis slots. Collection
  # leaves them empty; the analysis stage fills them as it advances.
  @enforce_keys [:execution, :phase, :definition, :snapshot_id, :tiers, :timing]
  defstruct [
    :execution,
    :phase,
    :definition,
    :snapshot_id,
    :timing,
    :request,
    :gust_run,
    :result,
    tiers: [],
    runs: []
  ]

  @type t :: %__MODULE__{
          execution: StudyExecution.t(),
          phase: StudyPhase.t(),
          definition: Definition.t(),
          snapshot_id: Ecto.UUID.t(),
          tiers: [String.t()],
          runs: [TierRun.t()],
          timing: TimingSummary.t(),
          request: term() | nil,
          gust_run: Gust.Flows.Run.t() | nil,
          result: term() | nil
        }

  # One collected tier, in declared order. The reference stays compact: the
  # stored Gust run owns the task history.
  defmodule TierRun do
    @moduledoc false

    @enforce_keys [:tier, :tier_position, :gust_run_id]
    defstruct [:tier, :tier_position, :gust_run_id]

    @type t :: %__MODULE__{
            tier: String.t(),
            tier_position: non_neg_integer(),
            gust_run_id: pos_integer()
          }
  end
end
