defmodule NetworkDefense.Simulation.Types.Action do
  @moduledoc false

  @behaviour Ecto.Type

  alias NetworkDefense.Actions.AcquireCredential
  alias NetworkDefense.Actions.ExploitVulnerability
  alias NetworkDefense.Actions.ReuseCredential
  alias NetworkDefense.Graph.Node

  def type, do: :map

  def embed_as(_format), do: :self
  def equal?(left, right), do: left == right

  def cast(%ExploitVulnerability{} = action), do: {:ok, action}
  def cast(%AcquireCredential{} = action), do: {:ok, action}
  def cast(%ReuseCredential{} = action), do: {:ok, action}
  def cast(value), do: load(value)

  def load(
        %{
          "type" => "exploit_vulnerability",
          "source_host_id" => source_host_id,
          "target_host_id" => target_host_id,
          "service_id" => service_id,
          "vulnerability_node_id" => vulnerability_node_id,
          "success_probability" => success_probability
        } = action
      )
      when is_binary(source_host_id) and is_binary(target_host_id) and is_binary(service_id) and
             is_binary(vulnerability_node_id) and is_number(success_probability) do
    with {:ok, required_privilege} <- privilege(Map.get(action, "required_privilege"), :none),
         {:ok, granted_privilege} <- privilege(Map.get(action, "granted_privilege"), :user) do
      {:ok,
       %ExploitVulnerability{
         source_host: %Node{id: source_host_id},
         target_host: %Node{id: target_host_id},
         service: %Node{id: service_id},
         vulnerability_node: %Node{id: vulnerability_node_id},
         success_probability: success_probability,
         required_privilege: required_privilege,
         granted_privilege: granted_privilege
       }}
    end
  end

  def load(%{
        "type" => "exploit_vulnerability",
        "source_host_id" => source_host_id,
        "service_id" => nil,
        "vulnerability_node_id" => vulnerability_node_id,
        "success_probability" => success_probability,
        "required_privilege" => required_privilege,
        "granted_privilege" => granted_privilege
      })
      when is_binary(source_host_id) and is_binary(vulnerability_node_id) and
             is_number(success_probability) and is_binary(required_privilege) and
             is_binary(granted_privilege) do
    with {:ok, required_privilege} <- privilege(required_privilege, :none),
         {:ok, granted_privilege} <- privilege(granted_privilege, :user) do
      {:ok,
       %ExploitVulnerability{
         source_host: %Node{id: source_host_id},
         target_host: nil,
         service: nil,
         vulnerability_node: %Node{id: vulnerability_node_id},
         success_probability: success_probability,
         required_privilege: required_privilege,
         granted_privilege: granted_privilege
       }}
    end
  end

  def load(%{
        "type" => "exploit_vulnerability",
        "source_host_id" => source_host_id,
        "target_host_id" => target_host_id,
        "service_id" => service_id,
        "vulnerability_node_id" => vulnerability_node_id,
        "success_probability" => success_probability,
        "required_privilege" => required_privilege,
        "granted_privilege" => granted_privilege
      })
      when is_binary(source_host_id) and is_binary(target_host_id) and is_binary(service_id) and
             is_binary(vulnerability_node_id) and is_number(success_probability) and
             is_binary(required_privilege) and is_binary(granted_privilege) do
    with {:ok, required_privilege} <- privilege(required_privilege, :none),
         {:ok, granted_privilege} <- privilege(granted_privilege, :user) do
      {:ok,
       %ExploitVulnerability{
         source_host: %Node{id: source_host_id},
         target_host: %Node{id: target_host_id},
         service: %Node{id: service_id},
         vulnerability_node: %Node{id: vulnerability_node_id},
         success_probability: success_probability,
         required_privilege: required_privilege,
         granted_privilege: granted_privilege
       }}
    end
  end

  def load(%{
        "type" => "acquire_credential",
        "credential_id" => credential_id,
        "host_id" => host_id
      })
      when is_binary(credential_id) and is_binary(host_id) do
    {:ok, %AcquireCredential{credential: %Node{id: credential_id}, host: %Node{id: host_id}}}
  end

  def load(%{
        "type" => "reuse_credential",
        "credential_id" => credential_id,
        "source_host_id" => source_host_id,
        "target_host_id" => target_host_id,
        "service_id" => service_id,
        "granted_privilege" => granted_privilege
      })
      when is_binary(credential_id) and is_binary(source_host_id) and is_binary(target_host_id) and
             is_binary(service_id) and is_binary(granted_privilege) do
    with {:ok, granted_privilege} <- privilege(granted_privilege, :user) do
      {:ok,
       %ReuseCredential{
         credential: %Node{id: credential_id},
         source_host: %Node{id: source_host_id},
         target_host: %Node{id: target_host_id},
         service: %Node{id: service_id},
         granted_privilege: granted_privilege
       }}
    end
  end

  def load(_), do: :error

  def dump(%ExploitVulnerability{} = action) do
    base = %{
      "type" => "exploit_vulnerability",
      "source_host_id" => action.source_host.id,
      "vulnerability_node_id" => action.vulnerability_node.id,
      "success_probability" => action.success_probability,
      "required_privilege" =>
        (action.required_privilege && Atom.to_string(action.required_privilege)) || "none",
      "granted_privilege" =>
        (action.granted_privilege && Atom.to_string(action.granted_privilege)) || "user"
    }

    result =
      case action.target_host do
        nil -> Map.put(base, "target_host_id", nil)
        %{id: id} -> Map.put(base, "target_host_id", id)
      end

    result =
      case action.service do
        nil -> Map.put(result, "service_id", nil)
        %{id: id} -> Map.put(result, "service_id", id)
      end

    {:ok, result}
  end

  def dump(%AcquireCredential{} = action) do
    {:ok,
     %{
       "type" => "acquire_credential",
       "credential_id" => action.credential.id,
       "host_id" => action.host.id
     }}
  end

  def dump(%ReuseCredential{} = action) do
    {:ok,
     %{
       "type" => "reuse_credential",
       "credential_id" => action.credential.id,
       "source_host_id" => action.source_host.id,
       "target_host_id" => action.target_host.id,
       "service_id" => action.service.id,
       "granted_privilege" => Atom.to_string(action.granted_privilege)
     }}
  end

  def dump(_), do: :error

  defp privilege(nil, default), do: {:ok, default}
  defp privilege("none", _default), do: {:ok, :none}
  defp privilege("user", _default), do: {:ok, :user}
  defp privilege("administrator", _default), do: {:ok, :administrator}

  defp privilege(privilege, _default) when privilege in [:none, :user, :administrator],
    do: {:ok, privilege}

  defp privilege(_privilege, _default), do: :error
end
