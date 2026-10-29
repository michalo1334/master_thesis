defmodule NetworkDefense.Evaluation2.Contracts.PhaseContract do
  @moduledoc """
  Boundary contract of one Gust phase run.

  A phase run takes one compact root input and returns one typed terminal success
  value. Gust status and its stored task error carry failure, so a phase contract
  declares no error union. An implementation encodes the root input into run
  params and decodes the stored terminal task result.
  """

  @typedoc "String-keyed Gust run params."
  @type params :: map()

  @typedoc "One decoded terminal success value."
  @type output :: term()

  @doc """
  Encode the compact root input into Gust run params.

  The params repeat phase or phase-run identity only. Evidence, definitions, and
  selections stay in application records that the phase loads.
  """
  @callback to_params(input :: term()) :: params()

  @doc """
  Decode one stored terminal task result into the typed phase output.

  The terminal task owns its scientific checks, so decoding reads a result that
  the task already accepted.
  """
  @callback decode_output!(params()) :: output()
end
