# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
alias NetworkDefense.Graph.Graphs
alias NetworkDefense.Topology.EnterpriseTopology

topology_specs = [
  {"Enterprise Topology (15 hosts)", 15, 15},
  {"Enterprise Topology (50 hosts)", 50, 50},
  {"Enterprise Topology (100 hosts)", 100, 100},
  {"Enterprise Topology (500 hosts)", 500, 500},
  {"Enterprise Topology (1000 hosts)", 1000, 1000}
]

existing_titles = Enum.map(Graphs.list_summaries(), & &1.title)

Enum.each(topology_specs, fn {title, hosts, seed} ->
  if title in existing_titles do
    IO.puts("#{title} already exists")
  else
    graph = EnterpriseTopology.generate(title: title, hosts: hosts, seed: seed)

    case Graphs.insert(graph) do
      {:ok, persisted} ->
        IO.puts("Seeded #{persisted.title} with #{hosts} hosts and seed #{seed}")

      {:error, reason} ->
        raise "failed to persist #{title}: #{inspect(reason)}"
    end
  end
end)
