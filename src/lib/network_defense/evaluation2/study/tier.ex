defmodule NetworkDefense.Evaluation2.Study.Tier do
  @moduledoc """
  Closed ordered network-size tier of one study.

  The order is `:small`, `:medium`, `:large`. `all/0` owns the order, and the
  position conversions state the same order once. Stored records keep a tier
  value and derive its position from this module.

  Pilot candidate identifiers name sample-size choices. They are unrelated to a
  tier.
  """

  use Spectral

  @typedoc "One declared network-size tier."
  @type t :: :small | :medium | :large

  @tiers [:small, :medium, :large]

  @doc "Return every tier in declared order."
  @spec all() :: [t()]
  def all, do: @tiers

  @doc "Return the declared position of one tier."
  @spec position(t()) :: 0..2
  def position(:small), do: 0
  def position(:medium), do: 1
  def position(:large), do: 2

  @doc "Return the tier at one declared position."
  @spec from_position(0..2) :: t()
  def from_position(0), do: :small
  def from_position(1), do: :medium
  def from_position(2), do: :large
end
