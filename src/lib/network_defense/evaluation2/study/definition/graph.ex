defmodule NetworkDefense.Evaluation2.Study.Definition.Graph do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Definition.Strategy

  # One declared network-size tier input.
  #
  # The graph references stay as declared identities until construction
  # resolves them and freezes the revision and the Host foothold. Budgets are
  # declared once per tier and shared by every alternative of that tier.
  #
  # `mission_impact_bound` is the finite derived mission-impact range with a
  # `minimum` and a `maximum`. Construction computes it from the resolved graph,
  # so no observation and no operator value ever replaces it. A map keeps the
  # two bounds readable in the stored representation.

  @typedoc "Frozen mission-impact range."
  @type mission_impact_bound :: %{minimum: float(), maximum: float()}

  @type t :: %__MODULE__{
          tier: String.t(),
          graph_revision_id: String.t(),
          initial_foothold_node_id: String.t(),
          budgets: [pos_integer()],
          alternatives: [Strategy.t()],
          mission_impact_bound: mission_impact_bound()
        }
  defstruct [
    :tier,
    :graph_revision_id,
    :initial_foothold_node_id,
    :budgets,
    :alternatives,
    :mission_impact_bound
  ]
end
