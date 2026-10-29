defmodule NetworkDefense.Evaluation2.WorkItem do
  @moduledoc false

  # One resolved collection request of a `CollectionPlan`.
  #
  # The planner writes the request once, and a mapped task decodes the stored
  # request instead of rebuilding canonical work from the definition. The
  # declared strategy group owns the budget and the scoring settings.
  #
  # Positions belong to `CollectionItem`. The comparison identity stays in the
  # immutable definition and is joined by position during analysis.

  alias NetworkDefense.Evaluation2.Seed
  alias NetworkDefense.Evaluation2.Side
  alias NetworkDefense.Evaluation2.Study.Definition

  @typedoc "Canonical graph revision identifier of the declared tier."
  @type graph_revision :: Ecto.UUID.t()

  @type t :: %__MODULE__{
          comparison_position: non_neg_integer(),
          side: Side.t(),
          graph_revision: graph_revision(),
          initial_foothold_node_id: Ecto.UUID.t() | nil,
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
