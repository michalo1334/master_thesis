defmodule NetworkDefense.Evaluation2.Study.RevisionContext do
  @moduledoc """
  Frozen provenance of one study revision.

  The application captured these values when the revision was created, and the
  definition owns them from then on. They are reported apart from the authored
  settings, because no operator declares them.

  `measurement_label` is nil when no measurement environment label was
  configured at creation. A revision created without one can still run Pilot
  work, and Final measured collection requires a configured label.
  """

  use Spectral

  @type t :: %__MODULE__{
          method: String.t(),
          seed_contract: String.t(),
          measurement_label: String.t() | nil
        }

  defstruct [:method, :seed_contract, :measurement_label]
end
