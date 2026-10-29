defmodule NetworkDefense.Evaluation2.Side do
  @moduledoc false

  # Side of one comparison observation.
  #
  # The alternative side runs the declared strategy under test. The reference
  # side runs the declared reference strategy. Both sides of one comparison share
  # one attack-column list.

  @typedoc "One side of a declared comparison."
  @type t :: :alternative | :reference
end
