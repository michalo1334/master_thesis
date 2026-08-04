# Benchmark comparing Enum.map vs parallel_map_fn for simulation runs.
#
# Builds canonical topology (segments, Contains, Runs, SegmentReachability),
# materializes the in-memory reachability projection, and runs without DB or
# app startup.
# Usage:
#   mix run --no-start priv/bench/map_fun_bench.exs

alias NetworkDefense.Graph.Graph
alias NetworkDefense.Graph.MaterializeReachability
alias NetworkDefense.Graph.Node
alias NetworkDefense.AttackerState.AttackerState
alias NetworkDefense.Nodes.Host
alias NetworkDefense.Nodes.NetworkSegment
alias NetworkDefense.Nodes.Service
alias NetworkDefense.Nodes.Vulnerability
alias NetworkDefense.Relationships.Contains
alias NetworkDefense.Relationships.HasVulnerability
alias NetworkDefense.Relationships.Runs
alias NetworkDefense.Relationships.SegmentReachability
alias NetworkDefense.Simulation.Simulator
alias NetworkDefense.Rules.RemoteServiceExploitation

{:ok, bench_sup} = Task.Supervisor.start_link(name: :bench_sup)

parallel_map_fn = fn enum, fun ->
  bench_sup
  |> Task.Supervisor.async_stream(enum, fun, ordered: false, timeout: :infinity)
  |> Enum.to_list()
end

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

host_names = ["internet", "edge-fw-01", "vpn-01", "web-01", "web-02"]

service_specs = [
  {"vpn", "vpn-01", "openvpn", "tcp", 1194, "2.6.0"},
  {"web-01", "web-01", "nginx", "tcp", 443, "1.22.1"},
  {"web-02", "web-02", "nginx", "tcp", 443, "1.22.1"}
]

vulnerability_specs = [
  {"nginx-path-traversal", "CVE-2021-41773", cvss.("high", "none", "none", "unchanged"), 0.45},
  {"vpn-arbitrary-file-read", "CVE-2019-11510", cvss.("high", "high", "high", "changed"), 0.8}
]

segment_specs = [
  {"external", "External", ["internet"]},
  {"edge", "Edge", ["edge-fw-01"]},
  {"app", "App", ["vpn-01", "web-01", "web-02"]}
]

policy_specs = [
  {"external", "app", 1194},
  {"edge", "app", 1194},
  {"edge", "app", 443}
]

vulnerability_assignments = [
  {"web-01", "nginx-path-traversal"},
  {"web-02", "nginx-path-traversal"},
  {"vpn", "vpn-arbitrary-file-read"}
]

new_node = fn graph, type, data ->
  Node.new(graph.id, %{type: type_id.(type), data: data, view_data: %{"x_pos" => 0, "y_pos" => 0}})
end

graph = Graph.new("Benchmark Graph")

{graph, hosts} =
  Enum.reduce(host_names, {graph, %{}}, fn host_name, {graph, hosts} ->
    host = new_node.(graph, Host, %{"name" => host_name})
    {Graph.add_node(graph, host), Map.put(hosts, host_name, host)}
  end)

{graph, segments} =
  Enum.reduce(segment_specs, {graph, %{}}, fn {segment_id, name, host_names}, {graph, segments} ->
    segment = new_node.(graph, NetworkSegment, %{"name" => name})

    graph =
      Enum.reduce(host_names, Graph.add_node(graph, segment), fn host_name, graph ->
        Graph.add_edge(graph, segment, Map.fetch!(hosts, host_name), %{
          type: type_id.(Contains),
          data: %{}
        })
      end)

    {graph, Map.put(segments, segment_id, segment)}
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

graph =
  Enum.reduce(policy_specs, graph, fn {source_segment, target_segment, port}, graph ->
    Graph.add_edge(
      graph,
      Map.fetch!(segments, source_segment),
      Map.fetch!(segments, target_segment),
      %{
        type: type_id.(SegmentReachability),
        data: %{"protocol" => "tcp", "port_start" => port, "port_end" => port}
      }
    )
  end)

graph =
  Enum.reduce(vulnerability_assignments, graph, fn {service_id, vulnerability_id}, graph ->
    Graph.add_edge(
      graph,
      Map.fetch!(services, service_id),
      Map.fetch!(vulnerabilities, vulnerability_id),
      %{
        type: type_id.(HasVulnerability),
        data: %{"required_privilege" => "none", "granted_privilege" => "user"}
      }
    )
  end)

graph = MaterializeReachability.materialize(graph)

node_count =
  length(host_names) + length(segment_specs) + length(service_specs) + length(vulnerability_specs)

IO.puts("In-memory graph: #{graph.id}, #{node_count} nodes")

run_count = 500
iteration_count = 500

opts = [
  run_count: run_count,
  iteration_count: iteration_count,
  seed: 0,
  rules: [%RemoteServiceExploitation{}]
]

initial_attacker_state = AttackerState.new(Map.fetch!(hosts, "internet").id)

IO.puts("Run count: #{run_count}, Iterations per run: #{iteration_count}")

IO.puts("\n=== Sequential (Enum.map) ===")

{seq_us, _seq_result} =
  :timer.tc(fn ->
    Simulator.run_experiment(
      graph,
      initial_attacker_state,
      Keyword.put(opts, :map_fn, &Enum.map/2)
    )
  end)

IO.puts("Wall time: #{div(seq_us, 1000)} ms")

IO.puts("\n=== Parallel (async_stream) ===")

{par_us, _par_result} =
  :timer.tc(fn ->
    Simulator.run_experiment(
      graph,
      initial_attacker_state,
      Keyword.put(opts, :map_fn, parallel_map_fn)
    )
  end)

IO.puts("Wall time: #{div(par_us, 1000)} ms")

Process.exit(bench_sup, :normal)

speedup = Float.round(seq_us / par_us, 2)

IO.puts("\n=== Summary ===")
IO.puts("Sequential: #{div(seq_us, 1000)} ms")
IO.puts("Parallel:   #{div(par_us, 1000)} ms")
IO.puts("Speedup:    #{speedup}x")
