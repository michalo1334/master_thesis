defmodule NetworkDefense.Evaluation2.Study.Cancel do
  @moduledoc """
  Cancellation policy of one study execution.

  Cancellation is a lifecycle event. It is accepted by every non-terminal state
  and ignored by a terminal state, so a late phase completion cannot advance a
  cancelled execution.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation2.StudyExecution

  @doc """
  Cancel one execution and return its stored record.

  Scaffold: returns `{:error, :not_implemented}`.
  """
  @spec cancel(Ecto.UUID.t()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t() | :not_implemented}
  def cancel(_execution_id), do: {:error, :not_implemented}
end
