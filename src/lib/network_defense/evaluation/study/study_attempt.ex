defmodule NetworkDefense.Evaluation.StudyAttempt do
  @moduledoc """
  One monitored study-analysis task attempt.

  `id` is a browser-safe opaque string that the task carries in every phase,
  result, and error event. The owner compares the message identity against the
  stored attempt instead of the pid, so a replaced or reused pid cannot move a
  stale message into the current attempt. The value crosses to the browser in
  the accepted start reply, so the client can require exact
  document/mode/attempt correlation and drop a delayed event from an earlier
  attempt in the same mode.

  `id` is never derived from user input. `new_id/0` generates it server-side
  from a cryptographic random source and URL-safe base64, so it stays opaque
  and safe for a wire payload.

  A non-nil attempt stays active until the owner consumes its result or its
  monitor `:DOWN` message. The owner never uses `Process.alive?/1` for that
  transition, because a task can send its result and exit before the owner runs.
  """

  @type mode :: :pilot | :final

  @enforce_keys [:id, :mode, :pid, :ref, :started_at]
  defstruct [:id, :mode, :pid, :ref, :started_at]

  @type t :: %__MODULE__{
          id: String.t(),
          mode: mode(),
          pid: pid(),
          ref: reference(),
          started_at: integer()
        }

  @doc "Generates one opaque, browser-safe attempt identity."
  @spec new_id() :: String.t()
  def new_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  @spec new(String.t(), mode(), pid(), reference()) :: t()
  def new(id, mode, pid, ref) when is_binary(id) and mode in [:pilot, :final] do
    %__MODULE__{
      id: id,
      mode: mode,
      pid: pid,
      ref: ref,
      started_at: System.monotonic_time()
    }
  end

  @spec mode(t()) :: mode()
  def mode(%__MODULE__{mode: mode}), do: mode
end
