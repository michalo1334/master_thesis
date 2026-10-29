defmodule NetworkDefense.Evaluation2.Study.Cancel do
  @moduledoc false

  # Cancellation policy of one study execution.
  #
  # Cancellation is a lifecycle event. Every non-terminal state accepts it, and a
  # terminal state returns its stored status. A late phase completion therefore
  # cannot advance a cancelled execution.

  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Status

  # Cancel one execution and return its status view.
  @spec cancel(Ecto.UUID.t()) :: {:ok, Status.t()} | {:error, Error.t()}
  def cancel(_execution_id), do: {:error, Placeholder.error(:cancel)}
end
