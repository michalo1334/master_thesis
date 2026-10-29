defmodule NetworkDefense.Evaluation2.Tier do
  @moduledoc """
  Network-size tier of one study.

  A study tier is exactly one network-size tier. The closed order is `:small`,
  then `:medium`, then `:large`, so a tier position is derivable and no Evaluation2
  record stores one. Pilot candidate identifiers name sample-size choices and stay
  plain candidate identifiers.

  `position/1` and `from_position/1` are the only tier-order conversions.
  """

  alias NetworkDefense.Evaluation2.NotImplementedError

  @typedoc "One declared network-size tier."
  @type t :: :small | :medium | :large

  @doc "Return every tier in declared order."
  @spec all() :: [t()]
  def all, do: raise(NotImplementedError, function: :all)

  @doc "Return the declared position of one tier."
  @spec position(t()) :: non_neg_integer()
  def position(_tier), do: raise(NotImplementedError, function: :position)

  @doc "Return the tier at one declared position, or `nil` above the last tier."
  @spec from_position(non_neg_integer()) :: t() | nil
  def from_position(_position), do: raise(NotImplementedError, function: :from_position)
end
