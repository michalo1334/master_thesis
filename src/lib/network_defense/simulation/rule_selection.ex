defmodule NetworkDefense.Simulation.RuleSelection do
  @moduledoc """
  Stable identifiers for executable simulation rules.

  The order is the default evaluation order used by the rule registry.
  """

  @values [
    :remote_service_exploitation,
    :local_vulnerability_exploitation,
    :acquire_credential_rule,
    :reuse_credential_rule
  ]

  @type rule_type ::
          :remote_service_exploitation
          | :local_vulnerability_exploitation
          | :acquire_credential_rule
          | :reuse_credential_rule

  @doc "Every declared rule identifier, in the default evaluation order."
  @spec values() :: [rule_type()]
  def values, do: @values
end
