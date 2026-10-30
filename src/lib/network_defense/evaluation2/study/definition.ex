defmodule NetworkDefense.Evaluation2.Study.Definition do
  @moduledoc false

  use Spectral

  # Study definition contract of the evaluation subsystem.
  #
  # The definition is the existing YAML contract: one normalized value that holds
  # the study identity, the scenario graphs, the simulation controls, the family,
  # and the Pilot, approval, and Final settings.
  #
  # `parse/1` belongs to the external creation boundary. Stored definitions are
  # decoded by `Study.Persistence` with Spectral, so later phases read trusted
  # typed data instead of repeating the check path.
  #
  # The declared graph tier is a definition string. Observed study data uses the
  # closed `NetworkDefense.Evaluation2.Study.Tier` order instead.

  alias NetworkDefense.Evaluation2.Study.Definition.{
    Candidate,
    Comparison,
    Family,
    Final,
    Graph,
    Pilot,
    PilotToFinal,
    Simulation,
    Strategy,
    Study
  }

  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Study.Error

  @typedoc "Normalized study definition, owned by Evaluation2."
  @type t :: %__MODULE__{
          schema_version: integer(),
          study: Study.t(),
          graphs: [Graph.t()],
          simulation: Simulation.t(),
          family: Family.t(),
          pilot: Pilot.t(),
          pilot_to_final: PilotToFinal.t(),
          final: Final.t()
        }

  defstruct [
    :schema_version,
    :study,
    :graphs,
    :simulation,
    :family,
    :pilot,
    :pilot_to_final,
    :final
  ]

  @typedoc "Declared comparison family."
  @type family :: Family.t()

  @typedoc "Declared Pilot candidate grid and settings."
  @type pilot :: Pilot.t()

  @typedoc "One declared family comparison."
  @type comparison :: Comparison.t()

  @typedoc "One declared plan-selection strategy group."
  @type strategy :: Strategy.t()

  @typedoc "One declared Pilot candidate."
  @type candidate :: Candidate.t()

  @typedoc "One declared graph of a network-size tier."
  @type graph :: Graph.t()

  # Parse one JSON-compatible YAML document into a normalized definition.
  #
  # Parsing rejects unknown fields, unrepresentable values, out-of-bound
  # settings, and a definition whose settings disagree.
  @spec parse(map()) :: {:ok, t()} | {:error, Error.t()}
  def parse(_attrs), do: raise(NotImplementedError, function: :parse)
end
