defmodule NetworkDefense.Evaluation2.Study.Collection.WorkItem do
  @moduledoc false

  use Spectral

  # One resolved collection request of a stored collection plan.
  #
  # The planner writes the request once, and a mapped task decodes the stored
  # request instead of rebuilding canonical work from the definition. The
  # declared strategy group owns the budget and the scoring settings.
  #
  # Positions belong to the collection item. The comparison identity stays in the
  # immutable definition and is joined by position during analysis. The foothold
  # is part of the resolved request: every stored item is later simulated.

  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Seed

  @typedoc "Canonical graph revision identifier of the declared tier."
  @type graph_revision :: Ecto.UUID.t()

  @typedoc """
  Side of one comparison observation.

  The alternative side runs the declared strategy under test. The reference side
  runs the declared reference strategy. Both sides of one comparison share one
  attack-column list.
  """
  @type side :: :alternative | :reference

  @type t :: %__MODULE__{
          comparison_position: non_neg_integer(),
          side: side(),
          graph_revision: graph_revision(),
          initial_foothold_node_id: Ecto.UUID.t(),
          strategy: Definition.strategy(),
          selection_seed: Seed.t(),
          evaluation_root: Seed.t(),
          attack_count: pos_integer()
        }

  defstruct [
    :comparison_position,
    :side,
    :graph_revision,
    :initial_foothold_node_id,
    :strategy,
    :selection_seed,
    :evaluation_root,
    :attack_count
  ]
end
