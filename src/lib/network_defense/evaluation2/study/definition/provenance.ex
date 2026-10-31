defmodule NetworkDefense.Evaluation2.Study.Definition.Provenance do
  @moduledoc false

  use Spectral

  # Frozen provenance captured during revision creation.
  #
  # These values identify the fixed method, the seed-derivation contract, and
  # the expected configured environment label. The application writes them;
  # the operator never declares them. Runtime facts belong to the execution.

  @type t :: %__MODULE__{
          method: String.t(),
          seed_contract: String.t(),
          environment_label: String.t() | nil
        }
  defstruct [:method, :seed_contract, :environment_label]
end
