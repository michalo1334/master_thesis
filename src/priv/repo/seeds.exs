# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
alias NetworkDefense.Graph.Graph
alias NetworkDefense.Graph.Graphs
alias NetworkDefense.Graph.Node
alias NetworkDefense.Nodes.Host
alias NetworkDefense.Nodes.Service
alias NetworkDefense.Nodes.Vulnerability
alias NetworkDefense.Relationships.HasVulnerability
alias NetworkDefense.Relationships.NetworkReachability
alias NetworkDefense.Relationships.Runs

type_id = &Atom.to_string/1

host_names = [
  "internet",
  "edge-fw-01",
  "vpn-01",
  "web-01",
  "web-02",
  "app-01",
  "app-02",
  "worker-01",
  "idp-01",
  "bastion-01",
  "git-01",
  "monitoring-01",
  "files-01",
  "db-01",
  "db-replica-01"
]

service_specs = [
  {"vpn", "vpn-01", "openvpn", "udp", 1194, "2.6.0"},
  {"web-01", "web-01", "nginx", "tcp", 443, "1.22.1"},
  {"web-02", "web-02", "nginx", "tcp", 443, "1.22.1"},
  {"app-01", "app-01", "api", "tcp", 8443, "3.4.1"},
  {"app-02", "app-02", "api", "tcp", 8443, "3.4.1"},
  {"worker", "worker-01", "amqp", "tcp", 5672, "3.12.2"},
  {"idp", "idp-01", "ldaps", "tcp", 636, "2.6.7"},
  {"bastion", "bastion-01", "ssh", "tcp", 22, "9.3"},
  {"git", "git-01", "gitlab", "tcp", 443, "16.7.0"},
  {"monitoring", "monitoring-01", "prometheus", "tcp", 9090, "2.47.0"},
  {"files", "files-01", "smb", "tcp", 445, "4.18.8"},
  {"db-primary", "db-01", "postgresql", "tcp", 5432, "15.5"},
  {"db-replica", "db-replica-01", "postgresql", "tcp", 5432, "15.5"}
]

vulnerability_specs = [
  {"nginx-path-traversal", "CVE-2021-41773", 7.5, 0.45},
  {"vpn-arbitrary-file-read", "CVE-2019-11510", 10.0, 0.8},
  {"identity-service-rce", "CVE-2021-44228", 10.0, 0.7},
  {"git-command-execution", "CVE-2022-24765", 7.8, 0.35},
  {"postgres-privilege-escalation", "CVE-2019-9193", 8.8, 0.3},
  {"api-http2-dos", "CVE-2023-44487", 7.5, 0.25}
]

reachability_specs = [
  {"internet", :host, "edge-fw-01"},
  {"edge-fw-01", :service, "vpn"},
  {"edge-fw-01", :service, "web-01"},
  {"edge-fw-01", :service, "web-02"},
  {"vpn-01", :service, "bastion"},
  {"bastion-01", :service, "idp"},
  {"bastion-01", :service, "git"},
  {"web-01", :service, "app-01"},
  {"web-02", :service, "app-02"},
  {"app-01", :service, "worker"},
  {"app-02", :service, "worker"},
  {"app-01", :service, "db-primary"},
  {"app-02", :service, "db-primary"},
  {"worker-01", :service, "db-replica"},
  {"worker-01", :service, "files"},
  {"git-01", :service, "files"},
  {"monitoring-01", :service, "app-01"},
  {"monitoring-01", :service, "app-02"},
  {"monitoring-01", :service, "db-primary"},
  {"db-01", :service, "db-replica"}
]

vulnerability_assignments = [
  {"web-01", "nginx-path-traversal"},
  {"web-02", "nginx-path-traversal"},
  {"vpn", "vpn-arbitrary-file-read"},
  {"idp", "identity-service-rce"},
  {"git", "git-command-execution"},
  {"db-primary", "postgres-privilege-escalation"},
  {"app-01", "api-http2-dos"},
  {"app-02", "api-http2-dos"}
]

new_node = fn graph, type, data ->
  Node.new(graph.id, %{type: type_id.(type), data: data})
end

graph = Graph.new("Enterprise Network")

{graph, hosts} =
  Enum.reduce(host_names, {graph, %{}}, fn host_name, {graph, hosts} ->
    host = new_node.(graph, Host, %{"name" => host_name})
    {Graph.add_node(graph, host), Map.put(hosts, host_name, host)}
  end)

{graph, services} =
  Enum.reduce(service_specs, {graph, %{}}, fn {service_id, host_name, name, protocol, port,
                                               version},
                                              {graph, services} ->
    service =
      new_node.(graph, Service, %{
        "name" => name,
        "protocol" => protocol,
        "port" => port,
        "version" => version
      })

    graph =
      graph
      |> Graph.add_node(service)
      |> Graph.add_edge(Map.fetch!(hosts, host_name), service, %{type: type_id.(Runs), data: %{}})

    {graph, Map.put(services, service_id, service)}
  end)

{graph, vulnerabilities} =
  Enum.reduce(vulnerability_specs, {graph, %{}}, fn {vulnerability_id, identifier, cvss_score,
                                                     exploit_probability},
                                                    {graph, vulnerabilities} ->
    vulnerability =
      new_node.(graph, Vulnerability, %{
        "identifier" => identifier,
        "cvss_score" => cvss_score,
        "exploit_probability" => exploit_probability
      })

    {Graph.add_node(graph, vulnerability),
     Map.put(vulnerabilities, vulnerability_id, vulnerability)}
  end)

graph =
  Enum.reduce(reachability_specs, graph, fn {source_host_name, target_kind, target_id}, graph ->
    target =
      case target_kind do
        :host -> Map.fetch!(hosts, target_id)
        :service -> Map.fetch!(services, target_id)
      end

    Graph.add_edge(
      graph,
      Map.fetch!(hosts, source_host_name),
      target,
      %{type: type_id.(NetworkReachability), data: %{}}
    )
  end)

graph =
  Enum.reduce(vulnerability_assignments, graph, fn {service_id, vulnerability_id}, graph ->
    Graph.add_edge(
      graph,
      Map.fetch!(services, service_id),
      Map.fetch!(vulnerabilities, vulnerability_id),
      %{type: type_id.(HasVulnerability), data: %{}}
    )
  end)

nodes = Graph.nodes(graph)
column_count = nodes |> length() |> :math.sqrt() |> Float.ceil() |> trunc() |> max(1)

graph =
  nodes
  |> Enum.with_index()
  |> Enum.reduce(graph, fn {node, index}, graph ->
    view_data = %{
      "x_pos" => 80 + rem(index, column_count) * 200,
      "y_pos" => 80 + div(index, column_count) * 120
    }

    Graph.update_node(graph, %{node | view_data: view_data})
  end)

{:ok, _graph} = Graphs.insert(graph)

IO.puts("Seeded enterprise graph #{graph.id} with #{length(host_names)} hosts")
