defmodule NetworkDefenseWeb.DashboardContractsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gen.Contracts.Registry
  alias NetworkDefenseWeb.Contracts

  alias NetworkDefenseWeb.Web.Contracts.{
    GraphContract,
    GraphMapper,
    RunSimulationRequest,
    SaveGraphPayload
  }

  test "all dashboard contracts are embedded schemas with changesets" do
    Registry.list_contract_modules()
    |> Enum.each(fn contract ->
      assert contract.__schema__(:source) == nil
      assert function_exported?(contract, :changeset, 2)
    end)
  end

  test "casts a graph payload and converts it back to domain attributes" do
    attrs = %{
      "graph" => %{
        "id" => "graph-1",
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
        "id" => "graph-1",
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
      "simulation_params" => %{"monte_carlo_trials" => 0, "iterations_per_count" => 1}
    }

    assert {:error, changeset} = RunSimulationRequest.validate(attrs)

    assert %{simulation_params: %{monte_carlo_trials: ["must be greater than 0"]}} =
             errors_on(changeset)
  end

  test "maps validated graph contracts to graph replacement attributes" do
    attrs = %{
      "id" => "graph-1",
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

    assert {:ok, graph} = GraphContract.validate(attrs)

    assert %{
             "title" => "Test graph",
             "nodes" => [
               %{
                 "id" => "node-1",
                 "type" => "Host",
                 "data" => %{"name" => "internet"},
                 "view_data" => %{"x_pos" => 120.0, "y_pos" => 240.0}
               }
             ],
             "edges" => []
           } = GraphMapper.to_attrs(graph)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
