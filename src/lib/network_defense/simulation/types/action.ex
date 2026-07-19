defmodule NetworkDefense.Simulation.Types.Action do
  @moduledoc false

  @behaviour Ecto.Type

  alias NetworkDefense.Actions.ExploitVulnerability
  alias NetworkDefense.Graph.Node

  def type, do: :map

  def embed_as(_format), do: :self
  def equal?(left, right), do: left == right

  def cast(%ExploitVulnerability{} = action), do: {:ok, action}
  def cast(value), do: load(value)

  def load(%{
        "type" => "exploit_vulnerability",
        "source_host_id" => source_host_id,
        "target_host_id" => target_host_id,
        "service_id" => service_id,
        "vulnerability_node_id" => vulnerability_node_id,
        "success_probability" => success_probability
      })
      when is_binary(source_host_id) and is_binary(target_host_id) and is_binary(service_id) and
             is_binary(vulnerability_node_id) and is_number(success_probability) do
    {:ok,
     %ExploitVulnerability{
       source_host: %Node{id: source_host_id},
       target_host: %Node{id: target_host_id},
       service: %Node{id: service_id},
       vulnerability_node: %Node{id: vulnerability_node_id},
       success_probability: success_probability
     }}
  end

  def load(_), do: :error

  def dump(%ExploitVulnerability{} = action) do
    {:ok,
     %{
       "type" => "exploit_vulnerability",
       "source_host_id" => action.source_host.id,
       "target_host_id" => action.target_host.id,
       "service_id" => action.service.id,
       "vulnerability_node_id" => action.vulnerability_node.id,
       "success_probability" => action.success_probability
     }}
  end

  def dump(_), do: :error
end
