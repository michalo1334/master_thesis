defmodule NetworkDefense.Simulation.Seed do
  @moduledoc """
  Shared seed manipulation: derivation, conversion, and generation.

  Used by the Simulator and simulation orchestration layer.
  """

  @default 0

  @typedoc "Opaque `:rand` seed state produced by `:rand.seed_s/2`."
  @type rand_state :: term()

  @doc "Default seed used when none is specified."
  def default, do: @default

  @doc """
  Generates a cryptographically random seed integer.

  Returned value fits in PostgreSQL `bigint` (signed 64-bit) so it can be
  persisted without overflow.
  """
  @spec random() :: integer()
  def random do
    :crypto.strong_rand_bytes(8)
    |> :binary.decode_unsigned()
    |> rem(9_223_372_036_854_775_807)
  end

  @doc """
  Derives a deterministic child seed from a parent seed and run index.

  Uses SHA-256 to produce an unsigned 64‑bit output modulo 2^63−1.
  """
  @spec child_seed(integer(), integer()) :: integer()
  def child_seed(parent_seed, index) when is_integer(parent_seed) and is_integer(index) do
    <<child_seed::unsigned-64, _::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary(parent_seed + index))

    rem(child_seed, 9_223_372_036_854_775_807)
  end

  @doc """
  Converts an integer seed into an `:rand.seed_s/1`-compatible `:exsss` seed tuple.
  """
  @spec integer_to_state(integer()) :: rand_state()
  def integer_to_state(seed) when is_integer(seed) do
    <<first::unsigned-32, second::unsigned-32, third::unsigned-32, _::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary(seed))

    :rand.seed_s(:exsss, {seed_part(first), seed_part(second), seed_part(third)})
  end

  @doc """
  Converts a seed to its `:rand` state representation.

  Passes through existing `:rand` seed tuples unchanged;
  integer seeds are converted via `integer_to_state/1`.
  """
  @spec seed_state(integer() | rand_state()) :: rand_state()
  def seed_state(seed) when is_integer(seed), do: integer_to_state(seed)
  def seed_state(seed), do: seed

  defp seed_part(value), do: rem(value, 2_147_483_646) + 1
end
