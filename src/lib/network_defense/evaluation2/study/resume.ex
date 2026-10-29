defmodule NetworkDefense.Evaluation2.Study.Resume do
  @moduledoc """
  Approval boundary of one study execution.

  Resume checks the request against the stored Pilot outcome, freezes the declared
  candidate with its two sample counts, and applies the lifecycle resume event.
  Final collection starts only after the transaction commits.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation2.StudyExecution

  @typedoc "Approval request: accept the recommendation or override an insufficient outcome."
  @type final_selection :: :recommended | {:override_insufficient, candidate_id :: String.t()}

  @doc """
  Accept one approval request.

  A request that names an undeclared candidate leaves the execution at
  `:awaiting_final` without an event. Scaffold: returns
  `{:error, :not_implemented}`.
  """
  @spec accept(Ecto.UUID.t(), final_selection()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t() | :not_implemented}
  def accept(_execution_id, _selection), do: {:error, :not_implemented}
end
