defmodule NetworkDefense.Evaluation2.Study.Lifecycle do
  @moduledoc false

  # Closed lifecycle of one study execution.
  #
  # Four states own an active phase, and only those states accept a terminal
  # phase failure. `:awaiting_final` is the explicit approval gate: it accepts
  # resume or cancellation.
  #
  # A terminal state keeps its state when a declared event arrives late or twice,
  # so terminal handling is idempotent. Gust owns detailed run progress; this
  # table owns the study lifecycle.

  alias NetworkDefense.Evaluation2.NotImplementedError

  @type state ::
          :collecting_pilot
          | :analyzing_pilot
          | :awaiting_final
          | :collecting_final
          | :analyzing_final
          | :succeeded
          | :failed
          | :cancelled

  @type event ::
          :pilot_collected
          | :pilot_analyzed
          | :resume
          | :final_collected
          | :final_analyzed
          | :fail
          | :cancel

  @spec initial_state() :: state()
  def initial_state, do: :collecting_pilot

  # An event that the state does not declare returns `{:error, :invalid_transition}`.
  @spec transition(state(), event()) :: {:ok, state()} | {:error, :invalid_transition}
  def transition(_state, _event), do: raise(NotImplementedError, function: :transition)
end
