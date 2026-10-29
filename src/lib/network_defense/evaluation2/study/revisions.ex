defmodule NetworkDefense.Evaluation2.Study.Revisions do
  @moduledoc false

  # Creation and trusted reads of frozen study revisions.
  #
  # Creation is the one external check point of a study: it parses the YAML
  # document, parses and checks the definition, checks the declared graph
  # references, and stores the normalized definition.
  #
  # Supported callers refer to a revision by its declared identity. The internal
  # identifier resolves that identity and stays behind this boundary.

  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefense.Evaluation2.StudyRevision

  # Freeze one revision from YAML text.
  @spec create(binary()) :: {:ok, Revision.t()} | {:error, Error.t()}
  def create(_document), do: {:error, Placeholder.error(:create)}

  # Resolve one declared revision identity to its stored record.
  @spec fetch!(Revision.t()) :: StudyRevision.t()
  def fetch!(_revision), do: raise(NotImplementedError, function: :fetch!)

  @spec load!(Ecto.UUID.t()) :: Definition.t()
  def load!(_revision_id), do: raise(NotImplementedError, function: :load!)
end
