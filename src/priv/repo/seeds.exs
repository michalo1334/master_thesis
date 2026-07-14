# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
alias NetworkDefense.Graph.Graph
alias NetworkDefense.Nodes.Host
alias NetworkDefense.Nodes.Service
alias NetworkDefense.Nodes.Vulnerability
alias NetworkDefense.Relationships.HasVulnerability
alias NetworkDefense.Relationships.NetworkReachability
alias NetworkDefense.Relationships.Runs
alias NetworkDefense.Repo

type_id = &Atom.to_string/1

{:ok, graph} =
  Repo.transaction(fn ->
    {:ok, graph} = Graph.create()

    {:ok, internet} =
      Graph.create_node(graph, %{type: type_id.(Host), data: %{"name" => "internet"}})

    {:ok, web_server} =
      Graph.create_node(graph, %{type: type_id.(Host), data: %{"name" => "web-01"}})

    {:ok, web_service} =
      Graph.create_node(graph, %{
        type: type_id.(Service),
        data: %{"name" => "nginx", "protocol" => "tcp", "port" => 443, "version" => "1.16.0"}
      })

    {:ok, vulnerability} =
      Graph.create_node(graph, %{
        type: type_id.(Vulnerability),
        data: %{
          "identifier" => "CVE-2019-9511",
          "cvss_score" => 7.5,
          "exploit_probability" => 0.8
        }
      })

    {:ok, _edge} =
      Graph.create_edge(graph, internet, web_service, %{type: type_id.(NetworkReachability)})

    {:ok, _edge} = Graph.create_edge(graph, web_server, web_service, %{type: type_id.(Runs)})

    {:ok, _edge} =
      Graph.create_edge(graph, web_service, vulnerability, %{type: type_id.(HasVulnerability)})

    graph
  end)

IO.puts("Seeded graph #{graph.id}")
