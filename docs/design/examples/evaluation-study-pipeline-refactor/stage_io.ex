defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.IO do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Pipeline.{Definition, StageAttempt}
  alias NetworkDefense.Evaluation.StudyExecution

  @enforce_keys [:execution, :stage, :definition]
  defstruct [:execution, :stage, :definition, :gust_run, :snapshot, work: [], items: []]

  @type t :: %__MODULE__{
          execution: StudyExecution.t(),
          stage: StageAttempt.t(),
          definition: Definition.t(),
          gust_run: term() | nil,
          snapshot: term() | nil,
          work: [term()],
          items: [Item.t()]
        }

  defmodule Item do
    @moduledoc false

    @enforce_keys [:collection_item]
    defstruct [:collection_item, :receipt]

    @type t :: %__MODULE__{
            collection_item: term(),
            receipt: term() | nil
          }
  end
end

defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.IO do
  @moduledoc false

  @enforce_keys [:execution, :stage, :definition, :snapshot]
  defstruct [
    :execution,
    :stage,
    :definition,
    :snapshot,
    :request,
    :gust_run,
    :result,
    :outcome,
    candidate_items: []
  ]

  @type t :: %__MODULE__{
          execution: term(),
          stage: term(),
          definition: term(),
          snapshot: term(),
          request: term() | nil,
          gust_run: term() | nil,
          result: term() | nil,
          outcome: term() | nil,
          candidate_items: [CandidateItem.t()]
        }

  defmodule CandidateItem do
    @moduledoc false

    @enforce_keys [:candidate, :comparison]
    defstruct [:candidate, :comparison, :result]

    @type t :: %__MODULE__{
            candidate: term(),
            comparison: term(),
            result: term() | nil
          }
  end
end

defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO do
  @moduledoc false

  @enforce_keys [:execution, :stage, :definition, :tiers]
  defstruct [:execution, :stage, :definition, :snapshot, tiers: [], timings: %{}]

  @type t :: %__MODULE__{
          execution: term(),
          stage: term(),
          definition: term(),
          snapshot: term() | nil,
          tiers: [Tier.t()],
          timings: map()
        }

  defmodule Tier do
    @moduledoc false

    @enforce_keys [:phase_io, :tier, :position]
    defstruct [:phase_io, :tier, :position, :stage_run, :gust_run, replicas: []]

    @type t :: %__MODULE__{
            phase_io: NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO.t(),
            tier: String.t(),
            position: non_neg_integer(),
            stage_run: term() | nil,
            gust_run: term() | nil,
            replicas: [Replica.t()]
          }
  end

  defmodule Replica do
    @moduledoc false

    @enforce_keys [:tier_io, :position]
    defstruct [:tier_io, :position, :timing, items: []]

    @type t :: %__MODULE__{
            tier_io: Tier.t(),
            position: -1 | non_neg_integer(),
            timing: term() | nil,
            items: [Item.t()]
          }
  end

  defmodule Item do
    @moduledoc false

    @enforce_keys [:collection_item]
    defstruct [:collection_item, :receipt]

    @type t :: %__MODULE__{
            collection_item: term(),
            receipt: term() | nil
          }
  end
end

defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO do
  @moduledoc false

  @enforce_keys [:execution, :stage, :definition, :snapshot]
  defstruct [
    :execution,
    :stage,
    :definition,
    :snapshot,
    :request,
    :gust_run,
    :result,
    comparison_items: []
  ]

  @type t :: %__MODULE__{
          execution: term(),
          stage: term(),
          definition: term(),
          snapshot: term(),
          request: term() | nil,
          gust_run: term() | nil,
          result: term() | nil,
          comparison_items: [ComparisonItem.t()]
        }

  defmodule ComparisonItem do
    @moduledoc false

    @enforce_keys [:comparison]
    defstruct [:comparison, :result]

    @type t :: %__MODULE__{
            comparison: term(),
            result: term() | nil
          }
  end
end
