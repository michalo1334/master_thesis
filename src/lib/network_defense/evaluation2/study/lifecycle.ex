defmodule NetworkDefense.Evaluation2.Study.Lifecycle do
  @moduledoc false

  # Closed lifecycle of one study execution.
  #
  # Four states own an active phase, and only those states accept a terminal
  # phase failure. `:awaiting_final` is the explicit approval gate: it accepts
  # resume or cancellation.
  #
  # This table describes single transitions only. Persistence decides how a
  # repeated or late command of one terminal state resolves. Gust owns detailed
  # run progress.

  @type state ::
          :collecting_pilot
          | :analyzing_pilot
          | :awaiting_final
          | :collecting_final
          | :analyzing_final
          | :succeeded
          | :failed
          | :cancelled

  @states [
    :collecting_pilot,
    :analyzing_pilot,
    :awaiting_final,
    :collecting_final,
    :analyzing_final,
    :succeeded,
    :failed,
    :cancelled
  ]

  @active_states [:collecting_pilot, :analyzing_pilot, :collecting_final, :analyzing_final]
  @cancellable_states @active_states ++ [:awaiting_final]

  @doc "Return every lifecycle state in declared order."
  @spec states() :: [state()]
  def states, do: @states

  @doc "Return the phase owned by an active lifecycle state."
  @spec phase(state()) ::
          :pilot_collection | :pilot_analysis | :final_collection | :final_analysis | nil
  def phase(:collecting_pilot), do: :pilot_collection
  def phase(:analyzing_pilot), do: :pilot_analysis
  def phase(:collecting_final), do: :final_collection
  def phase(:analyzing_final), do: :final_analysis
  def phase(_state), do: nil

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
  def transition(:collecting_pilot, :pilot_collected), do: {:ok, :analyzing_pilot}
  def transition(:analyzing_pilot, :pilot_analyzed), do: {:ok, :awaiting_final}
  def transition(:awaiting_final, :resume), do: {:ok, :collecting_final}
  def transition(:collecting_final, :final_collected), do: {:ok, :analyzing_final}
  def transition(:analyzing_final, :final_analyzed), do: {:ok, :succeeded}
  def transition(state, :fail) when state in @active_states, do: {:ok, :failed}
  def transition(state, :cancel) when state in @cancellable_states, do: {:ok, :cancelled}
  def transition(_state, _event), do: {:error, :invalid_transition}
end
