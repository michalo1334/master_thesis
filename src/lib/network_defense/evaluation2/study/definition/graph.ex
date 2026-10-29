defmodule NetworkDefense.Evaluation2.Study.Definition.Graph do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Definition.Strategy

  @type t :: %__MODULE__{
          tier: String.t(),
          graph_revision_id: String.t(),
          initial_foothold_node_id: String.t(),
          strategies: [Strategy.t()]
        }
  defstruct [:tier, :graph_revision_id, :initial_foothold_node_id, :strategies]
end
