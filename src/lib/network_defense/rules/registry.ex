defmodule NetworkDefense.Rules.Registry do
  @moduledoc """
  The authoritative registry of simulation rules.

  One declared list holds every rule module with its stable identifier. The
  order of the list is the default evaluation order, so the simulator default
  rule set and the resolved rule set of one request or experiment read the same
  declaration.

  The identifier is the contract value. JSON, YAML, and TypeScript carry it as a
  snake-case string because those formats have no atom type. The in-memory form
  is the atom, which `Ecto.Enum` materializes from the wire string.
  """

  alias NetworkDefense.Rules.{
    AcquireCredentialRule,
    LocalVulnerabilityExploitation,
    RemoteServiceExploitation,
    ReuseCredentialRule
  }

  @rules [
    remote_service_exploitation: RemoteServiceExploitation,
    local_vulnerability_exploitation: LocalVulnerabilityExploitation,
    acquire_credential_rule: AcquireCredentialRule,
    reuse_credential_rule: ReuseCredentialRule
  ]

  @values Keyword.keys(@rules)

  @type rule_type ::
          :remote_service_exploitation
          | :local_vulnerability_exploitation
          | :acquire_credential_rule
          | :reuse_credential_rule

  @doc "Every declared rule identifier, in the default evaluation order."
  @spec values() :: [rule_type()]
  def values, do: @values

  @doc "The rule module that one identifier names, or `nil`."
  @spec module_for(rule_type()) :: module() | nil
  def module_for(value), do: Keyword.get(@rules, value)

  @doc "The default rule structs, in the default evaluation order."
  @spec default_rules() :: [NetworkDefense.Rules.Rule.t()]
  def default_rules, do: Enum.map(@values, &struct(module_for(&1)))

  @doc """
  Resolves ordered rule identifiers to rule structs.

  The returned list keeps the order of the supplied identifiers. An empty list
  and an unknown identifier are rejected, so no caller runs a partial rule set.
  """
  @spec resolve([rule_type()]) :: {:ok, [struct()]} | {:error, :unknown_rule}
  def resolve(values) when is_list(values) and values != [] do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, rules} ->
      case module_for(value) do
        nil -> {:halt, {:error, :unknown_rule}}
        module -> {:cont, {:ok, [struct(module) | rules]}}
      end
    end)
    |> reverse_result()
  end

  def resolve(_values), do: {:error, :unknown_rule}

  defp reverse_result({:ok, rules}), do: {:ok, Enum.reverse(rules)}
  defp reverse_result({:error, reason}), do: {:error, reason}
end
