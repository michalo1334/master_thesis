defmodule NetworkDefenseWeb.DashboardContractsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gen.Contracts.Registry
  alias NetworkDefense.Contracts
  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Relationships.{HasVulnerability, NetworkReachability, Runs}
  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest

  alias NetworkDefenseWeb.Web.Contracts.SaveGraphPayload

  @graph_id "00000000-0000-0000-0000-000000000001"
  test "all dashboard contracts are embedded schemas with changesets" do
    Registry.list_contract_modules(:all)
    |> Enum.each(fn contract ->
      assert contract.__schema__(:source) == nil
      assert function_exported?(contract, :changeset, 2)
    end)
  end

  test "casts a graph payload and converts it back to domain attributes" do
    attrs = %{
      "graph" => %{
        "id" => @graph_id,
        "title" => "Test graph",
        "lock_version" => 1,
        "nodes" => [
          %{
            "id" => "node-1",
            "type" => "Host",
            "data" => %{"name" => "internet"},
            "view_data" => %{"x_pos" => 120, "y_pos" => 240}
          }
        ],
        "edges" => []
      }
    }

    assert {:ok, payload} = SaveGraphPayload.validate(attrs)
    assert %{name: "internet"} = payload.graph.nodes |> hd() |> Map.fetch!(:data)

    assert %{
             "title" => "Test graph",
             "nodes" => [
               %{
                 "id" => "node-1",
                 "type" => "Host",
                 "data" => %{"name" => "internet"},
                 "view_data" => %{"x_pos" => 120.0, "y_pos" => 240.0, "radius" => nil}
               }
             ],
             "edges" => []
           } = Contracts.to_params(payload.graph)
  end

  test "rejects invalid polymorphic node data" do
    attrs = %{
      "graph" => %{
        "id" => @graph_id,
        "title" => "Test graph",
        "lock_version" => 1,
        "nodes" => [
          %{
            "id" => "node-1",
            "type" => "Service",
            "data" => %{"name" => "dns", "protocol" => "icmp", "port" => 53},
            "view_data" => %{"x_pos" => 0, "y_pos" => 0}
          }
        ],
        "edges" => []
      }
    }

    assert {:error, changeset} = SaveGraphPayload.validate(attrs)
    assert %{graph: %{nodes: [%{data: ["is invalid"]}]}} = errors_on(changeset)
  end

  test "requires positive simulation parameters" do
    attrs = %{
      "graph_id" => "graph-1",
      "correlation_id" => "request-1",
      "simulation_params" => %{"monte_carlo_trials" => 0, "iterations_per_run" => 1}
    }

    assert {:error, changeset} = RunSimulationRequest.validate(attrs)

    assert %{simulation_params: %{monte_carlo_trials: ["must be greater than 0"]}} =
             errors_on(changeset)
  end

  test "maps validated graph contracts to canonical graph replacement attributes" do
    attrs = %{
      "id" => @graph_id,
      "title" => "Test graph",
      "lock_version" => 1,
      "nodes" => [
        %{
          "id" => "node-1",
          "type" => "Host",
          "data" => %{"name" => "internet"},
          "view_data" => %{"x_pos" => 120, "y_pos" => 240}
        }
      ],
      "edges" => []
    }

    assert {:ok,
            %{
              attrs: %{
                "title" => "Test graph",
                "nodes" => [
                  %{
                    "id" => "node-1",
                    "type" => type,
                    "data" => %{"name" => "internet"},
                    "view_data" => %{"x_pos" => 120.0, "y_pos" => 240.0}
                  }
                ],
                "edges" => []
              }
            }} = GraphContract.from_params(attrs)

    assert type == Atom.to_string(Host)
  end

  test "rejects persisted type names at the wire boundary" do
    for type <- [Atom.to_string(Host), "ok"] do
      assert {:error, changeset} =
               GraphContract.validate(%{
                 "id" => @graph_id,
                 "title" => "Test graph",
                 "lock_version" => 1,
                 "nodes" => [
                   %{
                     "id" => "node-1",
                     "type" => type,
                     "data" => %{"name" => "internet"},
                     "view_data" => %{"x_pos" => 0, "y_pos" => 0}
                   }
                 ],
                 "edges" => []
               })

      assert %{nodes: [%{type: ["is invalid"]}]} = errors_on(changeset)
    end
  end

  test "round trips every graph variant between the domain and wire contracts" do
    graph = Graph.new("Test graph")

    nodes = [
      %Node{
        id: "host",
        graph_id: graph.id,
        type: Atom.to_string(Host),
        data: %{"name" => "internet"},
        view_data: %{"x_pos" => 10, "y_pos" => 20, "radius" => 30}
      },
      %Node{
        id: "service",
        graph_id: graph.id,
        type: Atom.to_string(Service),
        data: %{"name" => "dns", "protocol" => "udp", "port" => 53},
        view_data: %{"x_pos" => 40, "y_pos" => 50}
      },
      %Node{
        id: "vulnerability",
        graph_id: graph.id,
        type: Atom.to_string(Vulnerability),
        data: %{
          "identifier" => "CVE-2026-0001",
          "cvss_score" => 7.5,
          "exploit_probability" => 0.4
        },
        view_data: %{"x_pos" => 70, "y_pos" => 80}
      }
    ]

    edges = [
      %Edge{
        id: "runs",
        graph_id: graph.id,
        from_id: "host",
        to_id: "service",
        type: Atom.to_string(Runs),
        data: %{}
      },
      %Edge{
        id: "reachable",
        graph_id: graph.id,
        from_id: "host",
        to_id: "service",
        type: Atom.to_string(NetworkReachability),
        data: %{}
      },
      %Edge{
        id: "vulnerable",
        graph_id: graph.id,
        from_id: "service",
        to_id: "vulnerability",
        type: Atom.to_string(HasVulnerability),
        data: %{}
      }
    ]

    graph = Graph.hydrate(graph, nodes, edges)

    assert {:ok, wire} = GraphContract.from_domain(graph)

    assert ["Host", "Service", "Vulnerability"] =
             wire
             |> Map.fetch!(:nodes)
             |> Enum.map(&Map.fetch!(&1, :type))
             |> Enum.sort()

    assert ["HasVulnerability", "NetworkReachability", "Runs"] =
             wire
             |> Map.fetch!(:edges)
             |> Enum.map(&Map.fetch!(&1, :type))
             |> Enum.sort()

    assert %{radius: 30.0} =
             wire
             |> Map.fetch!(:nodes)
             |> Enum.find(&(Map.fetch!(&1, :id) == "host"))
             |> Map.fetch!(:view_data)

    assert {:ok, %{attrs: attrs}} = GraphContract.from_params(wire)

    assert Enum.sort(Enum.map(attrs["nodes"], & &1["type"])) ==
             Enum.sort([
               Atom.to_string(Host),
               Atom.to_string(Service),
               Atom.to_string(Vulnerability)
             ])

    assert Enum.sort(Enum.map(attrs["edges"], & &1["type"])) ==
             Enum.sort([
               Atom.to_string(HasVulnerability),
               Atom.to_string(NetworkReachability),
               Atom.to_string(Runs)
             ])
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
