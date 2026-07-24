# Benchmark comparing Enum.map vs parallel_map_fn for simulation runs.
#
# Creates an in-memory graph and runs without DB or app startup.
# Usage:
#   mix run --no-start priv/bench/map_fun_bench.exs

alias NetworkDefense.Graph.Graph
alias NetworkDefense.Graph.Node
alias NetworkDefense.Nodes.Host
alias NetworkDefense.Nodes.Service
alias NetworkDefense.Nodes.Vulnerability
alias NetworkDefense.Relationships.HasVulnerability
alias NetworkDefense.Relationships.NetworkReachability
alias NetworkDefense.Relationships.Runs
alias NetworkDefense.Simulation.Simulator
alias NetworkDefense.Simulations
alias NetworkDefense.Rules.RemoteServiceExploitation

{:ok, bench_sup} = Task.Supervisor.start_link(name: :bench_sup)

parallel_map_fn = fn enum, fun ->
  bench_sup
  |> Task.Supervisor.async_stream(enum, fun, ordered: false, timeout: :infinity)
  |> Enum.to_list()
end

type_id = &Atom.to_string/1

host_names = ["internet", "edge-fw-01", "vpn-01", "web-01", "web-02"]

service_specs = [
  {"vpn", "vpn-01", "openvpn", "tcp", 1194, "2.6.0"},
  {"web-01", "web-01", "nginx", "tcp", 443, "1.22.1"},
  {"web-02", "web-02", "nginx", "tcp", 443, "1.22.1"}
]

vulnerability_specs = [
  {"nginx-path-traversal", "CVE-2021-41773", 7.5, 0.45},
  {"vpn-arbitrary-file-read", "CVE-2019-11510", 10.0, 0.8}
]

reachability_specs = [
  {"internet", :host, "edge-fw-01"},
  {"internet", :service, "vpn"},
  {"edge-fw-01", :service, "vpn"},
  {"edge-fw-01", :service, "web-01"},
  {"edge-fw-01", :service, "web-02"}
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

{graph, services} =
  Enum.reduce(service_specs, {graph, %{}}, fn {service_id, host_name, name, protocol, port, version},
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

node_count = length(host_names) + length(service_specs) + length(vulnerability_specs)
IO.puts("In-memory graph: #{graph.id}, #{node_count} nodes")

run_count = 500
iteration_count = 500

opts = [
  graph: graph,
  run_count: run_count,
  iteration_count: iteration_count,
  initial_attacker_state: Simulations.initial_attacker_state(graph),
  rules: [%RemoteServiceExploitation{}]
]

IO.puts("Run count: #{run_count}, Iterations per run: #{iteration_count}")

IO.puts("\n=== Sequential (Enum.map) ===")
{seq_us, _seq_result} =
  :timer.tc(fn ->
    Simulator.run_experiment(Keyword.put(opts, :map_fn, &Enum.map/2))
  end)
IO.puts("Wall time: #{div(seq_us, 1000)} ms")

IO.puts("\n=== Parallel (async_stream) ===")
{par_us, _par_result} =
  :timer.tc(fn ->
    Simulator.run_experiment(Keyword.put(opts, :map_fn, parallel_map_fn))
  end)
IO.puts("Wall time: #{div(par_us, 1000)} ms")

Process.exit(bench_sup, :normal)

speedup = Float.round(seq_us / par_us, 2)

IO.puts("\n=== Summary ===")
IO.puts("Sequential: #{div(seq_us, 1000)} ms")
IO.puts("Parallel:   #{div(par_us, 1000)} ms")
IO.puts("Speedup:    #{speedup}x")
