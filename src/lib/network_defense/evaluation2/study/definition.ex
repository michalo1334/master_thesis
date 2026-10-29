defmodule NetworkDefense.Evaluation2.Study.Definition do
  @moduledoc """
  Study definition contract of the replacement evaluation subsystem.

  The definition is the existing YAML contract: one normalized value that holds
  the study identity, the scenario graphs, the simulation controls, the family,
  and the Pilot, approval, and Final settings. `parse/1` belongs to the external
  creation boundary. `decode_stored!/1` reads a definition that creation already
  accepted.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.Definition, as: StoredDefinition
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation2.NotImplementedError

  @typedoc "Normalized study definition, reused from the existing YAML contract."
  @type t :: StoredDefinition.t()

  @doc """
  Parse one JSON-compatible YAML document into a normalized definition.

  Parsing rejects unknown fields, unrepresentable values, out-of-bound settings,
  and a definition whose settings disagree.
  """
  @spec parse(map()) :: {:ok, t()} | {:error, StudyError.t()}
  def parse(_attrs), do: raise(NotImplementedError, function: :parse)

  @doc "Decode one stored definition that creation already accepted."
  @spec decode_stored!(map()) :: t()
  def decode_stored!(_params), do: raise(NotImplementedError, function: :decode_stored!)
end
