defmodule NetworkDefense.Evaluation2.Study.Persistence.Error do
  @moduledoc false

  # Internal failure of one persistence operation.
  #
  # One struct replaces operation-specific tagged tuples, so every boundary read
  # and command reports a failure in the same shape. `Study.Views.error/1` maps
  # the value into the bounded public `Study.Error`.
  #
  # `cause` keeps Ecto, PostgreSQL, and Spectral diagnostics for internal logging.
  # It never enters a persisted record and never crosses the public boundary.

  @typedoc "Kind of one persistence failure."
  @type kind :: :not_found | :conflict | :storage | :corrupt_data

  @type t :: %__MODULE__{
          kind: kind(),
          operation: atom(),
          resource: atom(),
          cause: term()
        }

  defstruct [:kind, :operation, :resource, :cause]
end
