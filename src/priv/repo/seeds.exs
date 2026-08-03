# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
alias NetworkDefense.Graph.Graph
alias NetworkDefense.Graph.Graphs
alias NetworkDefense.Graph.Node
alias NetworkDefense.Nodes.Credential
alias NetworkDefense.Nodes.Host
alias NetworkDefense.Nodes.NetworkSegment
alias NetworkDefense.Nodes.Service
alias NetworkDefense.Nodes.Vulnerability
alias NetworkDefense.Relationships.AuthenticatesTo
alias NetworkDefense.Relationships.Contains
alias NetworkDefense.Relationships.HasVulnerability
alias NetworkDefense.Relationships.Runs
alias NetworkDefense.Relationships.SegmentReachability
alias NetworkDefense.Relationships.StoresCredential
alias NetworkDefense.Simulation.Seed

type_id = &Atom.to_string/1

cvss = fn confidentiality_impact, integrity_impact, availability_impact, scope ->
  %{
    "attack_vector" => "network",
    "attack_complexity" => "low",
    "privileges_required" => "none",
    "user_interaction" => "none",
    "scope" => scope,
    "confidentiality_impact" => confidentiality_impact,
    "integrity_impact" => integrity_impact,
    "availability_impact" => availability_impact
  }
end

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
  {"nginx-path-traversal", "CVE-2021-41773", cvss.("high", "none", "none", "unchanged"), 0.45},
  {"vpn-arbitrary-file-read", "CVE-2019-11510", cvss.("high", "high", "high", "changed"), 0.8},
  {"identity-service-rce", "CVE-2021-44228", cvss.("high", "high", "high", "changed"), 0.7},
  {"git-command-execution", "CVE-2022-24765", cvss.("high", "low", "low", "unchanged"), 0.35},
  {"bastion-ssh-command-execution", "CVE-2024-6387", cvss.("high", "high", "low", "unchanged"),
   0.9},
  {"postgres-privilege-escalation", "CVE-2019-9193", cvss.("high", "high", "high", "unchanged"),
   0.3},
  {"api-http2-dos", "CVE-2023-44487", cvss.("none", "none", "high", "unchanged"), 0.25}
]

credential_specs = [
  {"ssh-key-bastion", "bastion-admin-key", "ssh_key"},
  {"ssh-key-git", "git-deploy-key", "ssh_key"},
  {"db-password", "db-readonly-password", "password"}
]

# Host -> segment membership. Exactly one segment per host.
segment_assignments = [
  {"External", "internet"},
  {"DMZ", "edge-fw-01"},
  {"DMZ", "vpn-01"},
  {"DMZ", "web-01"},
  {"DMZ", "web-02"},
  {"Internal", "app-01"},
  {"Internal", "app-02"},
  {"Internal", "worker-01"},
  {"Internal", "git-01"},
  {"Internal", "files-01"},
  {"Restricted", "idp-01"},
  {"Restricted", "db-01"},
  {"Restricted", "db-replica-01"},
  {"Management", "bastion-01"},
  {"Management", "monitoring-01"}
]

# SegmentReachability NetworkSegment -> NetworkSegment policy rules.
# Each previous host/service flow becomes the rule between the source host's
# segment and the target service's host's segment, carrying the target
# service's protocol and port.
segment_policy_specs = [
  {"External", "DMZ", "udp", 1194},
  {"DMZ", "DMZ", "udp", 1194},
  {"DMZ", "DMZ", "tcp", 443},
  {"DMZ", "Management", "tcp", 22},
  {"Management", "Restricted", "tcp", 636},
  {"Management", "Internal", "tcp", 443},
  {"DMZ", "Internal", "tcp", 8443},
  {"Internal", "Internal", "tcp", 5672},
  {"Internal", "Restricted", "tcp", 5432},
  {"Internal", "Internal", "tcp", 445},
  {"Management", "Internal", "tcp", 8443},
  {"Management", "Restricted", "tcp", 5432},
  {"Restricted", "Restricted", "tcp", 5432}
]

# HasVulnerability Service -> Vulnerability with privilege defaults
vulnerability_assignments = [
  {"web-01", "nginx-path-traversal", "none", "user"},
  {"web-02", "nginx-path-traversal", "none", "user"},
  {"vpn", "vpn-arbitrary-file-read", "none", "user"},
  {"bastion", "bastion-ssh-command-execution", "user", "administrator"},
  {"idp", "identity-service-rce", "user", "administrator"},
  {"git", "git-command-execution", "user", "administrator"},
  {"db-primary", "postgres-privilege-escalation", "user", "administrator"},
  {"app-01", "api-http2-dos", "none", "user"},
  {"app-02", "api-http2-dos", "none", "user"}
]

# Local Host -> Vulnerability escalation example
local_vulnerability_assignments = [
  {"worker-01", "postgres-privilege-escalation", "user", "administrator"}
]

# StoresCredential: Host -> Credential
stores_credential_specs = [
  {"bastion-01", "ssh-key-bastion", "user"},
  {"git-01", "ssh-key-git", "user"},
  {"db-01", "db-password", "user"}
]

# AuthenticatesTo: Credential -> Service
authenticates_to_specs = [
  {"ssh-key-bastion", "bastion", "administrator"},
  {"ssh-key-git", "git", "administrator"},
  {"db-password", "db-primary", "user"}
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
  Enum.reduce(vulnerability_specs, {graph, %{}}, fn {vulnerability_id, identifier, cvss_data,
                                                     exploit_probability},
                                                    {graph, vulnerabilities} ->
    vulnerability =
      new_node.(graph, Vulnerability, %{
        "identifier" => identifier,
        "cvss" => cvss_data,
        "exploit_probability" => exploit_probability
      })

    {Graph.add_node(graph, vulnerability),
     Map.put(vulnerabilities, vulnerability_id, vulnerability)}
  end)

{graph, credentials} =
  Enum.reduce(credential_specs, {graph, %{}}, fn {credential_id, identifier, credential_type},
                                                 {graph, credentials} ->
    credential =
      new_node.(graph, Credential, %{
        "identifier" => identifier,
        "credential_type" => credential_type
      })

    {Graph.add_node(graph, credential), Map.put(credentials, credential_id, credential)}
  end)

{graph, segments} =
  segment_assignments
  |> Enum.map(&elem(&1, 0))
  |> Enum.uniq()
  |> Enum.reduce({graph, %{}}, fn segment_name, {graph, segments} ->
    segment = new_node.(graph, NetworkSegment, %{"name" => segment_name})
    {Graph.add_node(graph, segment), Map.put(segments, segment_name, segment)}
  end)

# Contains NetworkSegment -> Host, exactly one per host
graph =
  Enum.reduce(segment_assignments, graph, fn {segment_name, host_name}, graph ->
    Graph.add_edge(
      graph,
      Map.fetch!(segments, segment_name),
      Map.fetch!(hosts, host_name),
      %{type: type_id.(Contains), data: %{}}
    )
  end)

# SegmentReachability NetworkSegment -> NetworkSegment policy rules only
graph =
  Enum.reduce(segment_policy_specs, graph, fn {from_segment, to_segment, protocol, port}, graph ->
    Graph.add_edge(
      graph,
      Map.fetch!(segments, from_segment),
      Map.fetch!(segments, to_segment),
      %{
        type: type_id.(SegmentReachability),
        data: %{"protocol" => protocol, "port_start" => port, "port_end" => port}
      }
    )
  end)

# HasVulnerability Service -> Vulnerability
graph =
  Enum.reduce(vulnerability_assignments, graph, fn {service_id, vulnerability_id, required_priv,
                                                    granted_priv},
                                                   graph ->
    Graph.add_edge(
      graph,
      Map.fetch!(services, service_id),
      Map.fetch!(vulnerabilities, vulnerability_id),
      %{
        type: type_id.(HasVulnerability),
        data: %{
          "required_privilege" => required_priv,
          "granted_privilege" => granted_priv
        }
      }
    )
  end)

# Local Host -> Vulnerability escalation
graph =
  Enum.reduce(local_vulnerability_assignments, graph, fn {host_name, vulnerability_id,
                                                          required_priv, granted_priv},
                                                         graph ->
    Graph.add_edge(
      graph,
      Map.fetch!(hosts, host_name),
      Map.fetch!(vulnerabilities, vulnerability_id),
      %{
        type: type_id.(HasVulnerability),
        data: %{
          "required_privilege" => required_priv,
          "granted_privilege" => granted_priv
        }
      }
    )
  end)

# StoresCredential: Host -> Credential
graph =
  Enum.reduce(stores_credential_specs, graph, fn {host_name, credential_id, required_priv},
                                                 graph ->
    Graph.add_edge(
      graph,
      Map.fetch!(hosts, host_name),
      Map.fetch!(credentials, credential_id),
      %{
        type: type_id.(StoresCredential),
        data: %{"required_privilege" => required_priv}
      }
    )
  end)

# AuthenticatesTo: Credential -> Service
graph =
  Enum.reduce(authenticates_to_specs, graph, fn {credential_id, service_id, granted_priv},
                                                graph ->
    Graph.add_edge(
      graph,
      Map.fetch!(credentials, credential_id),
      Map.fetch!(services, service_id),
      %{
        type: type_id.(AuthenticatesTo),
        data: %{"granted_privilege" => granted_priv}
      }
    )
  end)

nodes = Graph.nodes(graph)
column_count = nodes |> length() |> :math.sqrt() |> Float.ceil() |> trunc() |> max(1)

graph =
  nodes
  |> Enum.with_index()
  |> Enum.reduce(graph, fn {node, index}, graph ->
    view_data = %{
      x_pos: 80 + rem(index, column_count) * 200,
      y_pos: 80 + div(index, column_count) * 120,
      radius: nil
    }

    Graph.update_node(graph, %{node | view_data: view_data})
  end)

case Enum.any?(Graphs.list_summaries(), &(&1.title == graph.title)) do
  false ->
    {:ok, _graph} = Graphs.insert(graph)
    IO.puts("Seeded enterprise graph #{graph.id} with #{length(host_names)} hosts")

  true ->
    IO.puts("#{graph.title} already exists")
end

Enum.each([500, 1_000, 2_000], fn node_count ->
  performance_title = "Performance Topology (#{node_count} nodes)"

  case Enum.any?(Graphs.list_summaries(), &(&1.title == performance_title)) do
    false ->
      segment_count = 10
      budget = node_count - segment_count
      host_count = div(budget * 2, 5)
      service_count = host_count
      vulnerability_count = div(budget, 5)
      performance_seed = node_count
      performance_host_names = ["internet" | Enum.map(1..(host_count - 1), &"host-#{&1}")]
      segment_names = Enum.map(1..segment_count, &"segment-#{&1}")
      host_segments = Enum.zip(performance_host_names, Stream.cycle(segment_names))
      host_segment_map = Map.new(host_segments)

      service_templates = [
        {"http", "tcp", 80, "2.4.0"},
        {"https", "tcp", 443, "1.22.0"},
        {"ssh", "tcp", 22, "9.0"},
        {"database", "tcp", 5432, "15.0"},
        {"dns", "udp", 53, "9.18.0"}
      ]

      performance_graph = Graph.new(performance_title)

      {performance_graph, performance_hosts} =
        Enum.reduce(performance_host_names, {performance_graph, %{}}, fn host_name,
                                                                         {graph, hosts} ->
          host = new_node.(graph, Host, %{"name" => host_name})
          {Graph.add_node(graph, host), Map.put(hosts, host_name, host)}
        end)

      {performance_graph, performance_segments} =
        Enum.reduce(segment_names, {performance_graph, %{}}, fn segment_name, {graph, segments} ->
          segment = new_node.(graph, NetworkSegment, %{"name" => segment_name})
          {Graph.add_node(graph, segment), Map.put(segments, segment_name, segment)}
        end)

      # Contains NetworkSegment -> Host, exactly one per host
      performance_graph =
        Enum.reduce(host_segments, performance_graph, fn {host_name, segment_name}, graph ->
          Graph.add_edge(
            graph,
            Map.fetch!(performance_segments, segment_name),
            Map.fetch!(performance_hosts, host_name),
            %{type: type_id.(Contains), data: %{}}
          )
        end)

      {performance_graph, performance_services, service_flows, random_state} =
        Enum.reduce(
          1..service_count,
          {performance_graph, [], %{}, Seed.integer_to_state(performance_seed)},
          fn index, {graph, services, flows, state} ->
            {template_index, state} = :rand.uniform_s(length(service_templates), state)
            {name, protocol, port, version} = Enum.at(service_templates, template_index - 1)

            service =
              new_node.(graph, Service, %{
                "name" => "#{name}-#{index}",
                "protocol" => protocol,
                "port" => port,
                "version" => version
              })

            host = Map.fetch!(performance_hosts, Enum.at(performance_host_names, index - 1))

            graph =
              graph
              |> Graph.add_node(service)
              |> Graph.add_edge(host, service, %{type: type_id.(Runs), data: %{}})

            {graph, [service | services],
             Map.put(flows, service.id, %{protocol: protocol, port: port}), state}
          end
        )

      performance_services = Enum.reverse(performance_services)

      {performance_graph, random_state} =
        Enum.reduce(1..vulnerability_count, {performance_graph, random_state}, fn index,
                                                                                  {graph, state} ->
          {confidentiality_index, state} = :rand.uniform_s(3, state)
          {integrity_index, state} = :rand.uniform_s(3, state)
          {availability_index, state} = :rand.uniform_s(3, state)
          {probability_tenths, state} = :rand.uniform_s(9, state)

          impact = fn index -> Enum.at(["none", "low", "high"], index - 1) end

          vulnerability =
            new_node.(graph, Vulnerability, %{
              "identifier" => "PERF-#{index}",
              "cvss" =>
                cvss.(
                  impact.(confidentiality_index),
                  impact.(integrity_index),
                  impact.(availability_index),
                  "unchanged"
                ),
              "exploit_probability" => probability_tenths / 10
            })

          graph =
            graph
            |> Graph.add_node(vulnerability)
            |> Graph.add_edge(Enum.at(performance_services, index - 1), vulnerability, %{
              type: type_id.(HasVulnerability),
              data: %{"required_privilege" => "none", "granted_privilege" => "user"}
            })

          {graph, state}
        end)

      # SegmentReachability policy rules, three per host segment, matching the
      # target service's protocol and port
      {performance_graph, _random_state} =
        Enum.reduce(performance_host_names, {performance_graph, random_state}, fn host_name,
                                                                                  {graph, state} ->
          host_segment = Map.fetch!(host_segment_map, host_name)

          Enum.reduce(1..3, {graph, state}, fn _, {graph, state} ->
            {service_index, state} = :rand.uniform_s(vulnerability_count, state)
            service = Enum.at(performance_services, service_index - 1)

            target_segment =
              Map.fetch!(host_segment_map, Enum.at(performance_host_names, service_index - 1))

            flow = Map.fetch!(service_flows, service.id)

            graph =
              Graph.add_edge(
                graph,
                Map.fetch!(performance_segments, host_segment),
                Map.fetch!(performance_segments, target_segment),
                %{
                  type: type_id.(SegmentReachability),
                  data: %{
                    "protocol" => flow.protocol,
                    "port_start" => flow.port,
                    "port_end" => flow.port
                  }
                }
              )

            {graph, state}
          end)
        end)

      performance_nodes = Graph.nodes(performance_graph)

      performance_column_count =
        performance_nodes |> length() |> :math.sqrt() |> Float.ceil() |> trunc()

      performance_graph =
        performance_nodes
        |> Enum.with_index()
        |> Enum.reduce(performance_graph, fn {node, index}, graph ->
          Graph.update_node(graph, %{
            node
            | view_data: %{
                x_pos: 80 + rem(index, performance_column_count) * 200,
                y_pos: 80 + div(index, performance_column_count) * 120,
                radius: nil
              }
          })
        end)

      unless length(Graph.nodes(performance_graph)) == node_count do
        raise "performance topology must contain #{node_count} nodes"
      end

      edge_count = service_count + vulnerability_count + host_count + host_count * 3

      unless length(Graph.edges(performance_graph)) == edge_count do
        raise "performance topology must contain #{edge_count} edges"
      end

      {:ok, persisted_performance_graph} = Graphs.insert(performance_graph)

      unless length(Graph.nodes(persisted_performance_graph)) == node_count do
        raise "persisted performance topology must contain #{node_count} nodes"
      end

      unless length(Graph.edges(persisted_performance_graph)) == edge_count do
        raise "persisted performance topology must contain #{edge_count} edges"
      end

      IO.puts("Seeded #{performance_title} with seed #{performance_seed}")

    true ->
      IO.puts("#{performance_title} already exists")
  end
end)
