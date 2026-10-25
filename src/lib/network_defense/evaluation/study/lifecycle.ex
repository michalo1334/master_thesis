defmodule NetworkDefense.Evaluation.Study.Lifecycle do
  @moduledoc false

  # Pure study lifecycle.
  #
  # One execution holds one of these closed states. Four states own an active
  # phase, so only those four states accept a terminal phase failure. The Final
  # gate is not an active phase: a rejected resume request leaves the execution
  # at `:awaiting_final` without an event, and cancellation is the only event
  # that gate accepts besides resume.
  #
  # A terminal state keeps its state when a declared event arrives late or is
  # repeated. This makes terminal handling idempotent.

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

  @initial_state :collecting_pilot

  @events [
    :pilot_collected,
    :pilot_analyzed,
    :resume,
    :final_collected,
    :final_analyzed,
    :fail,
    :cancel
  ]

  # Progress through the four fixed phases, in their declared order.
  @progress [
    {:collecting_pilot, :pilot_collected, :analyzing_pilot},
    {:analyzing_pilot, :pilot_analyzed, :awaiting_final},
    {:awaiting_final, :resume, :collecting_final},
    {:collecting_final, :final_collected, :analyzing_final},
    {:analyzing_final, :final_analyzed, :succeeded}
  ]

  # States that own an active phase. Only an active phase can fail.
  @active_states [:collecting_pilot, :analyzing_pilot, :collecting_final, :analyzing_final]

  # Every state that is not terminal accepts cancellation.
  @nonterminal_states @active_states ++ [:awaiting_final]
  @terminal_states [:succeeded, :failed, :cancelled]

  @transitions @progress ++
                 for(state <- @active_states, do: {state, :fail, :failed}) ++
                 for(state <- @nonterminal_states, do: {state, :cancel, :cancelled}) ++
                 for(state <- @terminal_states, event <- @events, do: {state, event, state})

  @spec initial_state() :: state()
  def initial_state, do: @initial_state

  @spec transition(state(), event()) :: {:ok, state()} | {:error, :invalid_transition}
  def transition(state, event) do
    case Enum.find(@transitions, fn {source, accepted, _next} ->
           source == state and accepted == event
         end) do
      nil -> {:error, :invalid_transition}
      {_source, _event, next} -> {:ok, next}
    end
  end
end
