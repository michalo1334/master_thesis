defmodule NetworkDefense.Evaluation2.Study.Resume do
  @moduledoc false

  # Approval boundary of one study execution.
  #
  # Resume checks the approval intent against the stored Pilot outcome, resolves
  # the declared candidate, freezes its two sample counts, and applies the
  # lifecycle resume event. Final collection starts after the transaction
  # commits.
  #
  # The caller states intent only. Sample counts always come from the declared
  # candidate.

  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Status

  # Accept one approval intent and return the committed status view.
  #
  # An intent that names an undeclared candidate leaves the execution at
  # `:awaiting_final` and returns a bounded error.
  @spec accept(Ecto.UUID.t(), Study.approval()) :: {:ok, Status.t()} | {:error, Error.t()}
  def accept(_execution_id, _approval), do: {:error, Placeholder.error(:accept)}
end
