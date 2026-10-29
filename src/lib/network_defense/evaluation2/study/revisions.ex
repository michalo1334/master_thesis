defmodule NetworkDefense.Evaluation2.Study.Revisions do
  @moduledoc """
  Creation and trusted reads of frozen study revisions.

  Creation is the one external check point of a study: it parses the YAML
  document, parses and checks the definition, checks the declared graph
  references, and stores the normalized definition. Every later read decodes data
  that creation already accepted.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.StudyRevision

  @doc """
  Freeze one revision from YAML text.

  The stored revision keeps the normalized definition, so collection and analysis
  phases read one trusted value. Scaffold: returns `{:error, :not_implemented}`.
  """
  @spec create(binary()) ::
          {:ok, StudyRevision.t()} | {:error, StudyError.t() | :not_implemented}
  def create(_document), do: {:error, :not_implemented}

  @doc "Load the normalized definition of one frozen revision."
  @spec load!(Ecto.UUID.t()) :: Definition.t()
  def load!(_revision_id), do: raise(NotImplementedError, function: :load!)
end
