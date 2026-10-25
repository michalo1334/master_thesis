defmodule NetworkDefense.Evaluation.Study.LifecycleTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.Study.Lifecycle

  # Unit behaviors of the pure study lifecycle:
  #
  # 1. every accepted phase event declares one next state;
  # 2. an event that the current state does not accept returns
  #    `:invalid_transition`.
  #
  # The tables below are the lifecycle declaration, not a full state and event
  # matrix. Failure is accepted only by an active phase, cancellation is
  # accepted by every nonterminal state, and declared events keep terminal
  # states unchanged.

  @progress [
    {:collecting_pilot, :pilot_collected, :analyzing_pilot},
    {:analyzing_pilot, :pilot_analyzed, :awaiting_final},
    {:awaiting_final, :resume, :collecting_final},
    {:collecting_final, :final_collected, :analyzing_final},
    {:analyzing_final, :final_analyzed, :succeeded}
  ]

  @active [:collecting_pilot, :analyzing_pilot, :collecting_final, :analyzing_final]

  @nonterminal @active ++ [:awaiting_final]

  @terminal_idempotency [
    {:succeeded, :final_analyzed},
    {:succeeded, :cancel},
    {:failed, :pilot_collected},
    {:cancelled, :cancel}
  ]

  test "STUDY-LIFE-01: an accepted event returns its declared next state" do
    assert Lifecycle.initial_state() == :collecting_pilot

    for {state, event, next} <- @progress do
      assert Lifecycle.transition(state, event) == {:ok, next}
    end

    for state <- @active do
      assert Lifecycle.transition(state, :fail) == {:ok, :failed}
    end

    for state <- @nonterminal do
      assert Lifecycle.transition(state, :cancel) == {:ok, :cancelled}
    end

    for {state, event} <- @terminal_idempotency do
      assert Lifecycle.transition(state, event) == {:ok, state}
    end
  end

  test "STUDY-LIFE-02: an unaccepted event returns invalid_transition" do
    rejected = [
      # Pilot analysis cannot finish before Pilot collection.
      {:collecting_pilot, :pilot_analyzed},
      # A Final event cannot arrive during Pilot collection.
      {:collecting_pilot, :final_collected},
      # The Final gate is not an active phase, so it cannot fail.
      {:awaiting_final, :fail},
      # Resume belongs to the Final gate only.
      {:collecting_final, :resume}
    ]

    for {state, event} <- rejected do
      assert Lifecycle.transition(state, event) == {:error, :invalid_transition}
    end
  end
end
