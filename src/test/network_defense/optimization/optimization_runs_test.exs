defmodule NetworkDefense.Optimization.OptimizationRunsTest do
  use NetworkDefense.DataCase, async: true

  import Ecto.Query

  alias NetworkDefense.Graph.{Edge, Graph, Graphs}
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, NetworkSegment}
  alias NetworkDefense.Optimization.Contracts.{OptimizationParams, RunOptimizationRequest}
  alias NetworkDefense.Optimization.OptimizationAction
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Simulation.Contracts.SimulationParams

  describe "OptimizationRuns" do
    test "creates a run as running and completes it atomically with its actions" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())
      credential = Graph.nodes(graph) |> List.first()

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 2
               )
               |> OptimizationRuns.create()

      assert run.status == "running"

      assert {:ok, completed} =
               OptimizationRuns.complete(run, %{
                 actions: [
                   %{
                     action_type: "RevokeCredential",
                     target_id: credential.id,
                     cost: 1
                   }
                 ],
                 used_budget: 1,
                 runtime_ms: 12,
                 output_graph_revision_id: graph.revision_id
               })

      assert completed.status == "completed"
      assert completed.used_budget == 1
      assert completed.runtime_ms == 12
      assert completed.output_graph_revision_id == graph.revision_id

      assert %{actions: [saved]} = OptimizationRuns.load(run.id)
      assert saved.position == 1
      assert saved.action_type == "RevokeCredential"
      assert saved.target_id == credential.id
      assert saved.cost == 1
    end

    test "rolls back the completion when an action is invalid" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 2
               )
               |> OptimizationRuns.create()

      assert {:error, %Ecto.Changeset{}} =
               OptimizationRuns.complete(run, %{
                 actions: [
                   %{action_type: "RevokeCredential"}
                 ],
                 used_budget: 1,
                 runtime_ms: 1,
                 output_graph_revision_id: graph.revision_id
               })

      assert %{status: "running", used_budget: 0} = OptimizationRuns.load(run.id)
    end

    test "rolls back the output revision when run completion fails" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 1
               )
               |> OptimizationRuns.create()

      assert {:error, %Ecto.Changeset{}} =
               Graphs.append_optimization(graph, fn persisted ->
                 OptimizationRuns.complete(run, %{
                   actions: [%{action_type: "RevokeCredential"}],
                   used_budget: 1,
                   runtime_ms: 1,
                   output_graph_revision_id: persisted.revision_id
                 })
               end)

      assert [%{revisionId: revision_id}] =
               Graphs.list_summaries() |> Enum.filter(&(&1.graphId == graph.id))

      assert revision_id == graph.revision_id
      assert %{status: "running"} = OptimizationRuns.load(run.id)
    end

    test "fails a running run" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 1
               )
               |> OptimizationRuns.create()

      assert {:ok, failed} = OptimizationRuns.fail(run.id)
      assert failed.status == "failed"
    end

    test "fail/1 only transitions running runs" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 1
               )
               |> OptimizationRuns.create()

      assert {:ok, _completed} =
               OptimizationRuns.complete(run, %{
                 actions: [],
                 used_budget: 0,
                 runtime_ms: 1,
                 output_graph_revision_id: graph.revision_id
               })

      assert OptimizationRuns.fail(run.id) == :ok
      assert %{status: "completed"} = OptimizationRuns.load(run.id)
    end

    test "load/1 returns nil for an unknown run" do
      assert OptimizationRuns.load(Ecto.UUID.generate()) == nil
    end

    test "persists reproducibility inputs through create, complete, and load" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      simulation_config = %{
        trials: 20,
        iterations: 10,
        initial_foothold: "host-1",
        max_attempts: 3
      }

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "simulated_annealing",
                 requested_budget: 2,
                 seed: 42,
                 simulation_config: simulation_config
               )
               |> OptimizationRuns.create()

      assert run.seed == 42
      assert run.simulation_config == simulation_config

      assert {:ok, _completed} =
               OptimizationRuns.complete(run, %{
                 actions: [],
                 used_budget: 0,
                 runtime_ms: 1,
                 output_graph_revision_id: graph.revision_id
               })

      assert %{seed: 42, simulation_config: %{"trials" => 20, "iterations" => 10}} =
               OptimizationRuns.load(run.id)
    end

    test "rejects a negative seed" do
      changeset =
        OptimizationRun.changeset(%OptimizationRun{}, %{
          graph_revision_id: Ecto.UUID.generate(),
          strategy: "cvss",
          requested_budget: 1,
          seed: -1
        })

      refute changeset.valid?
      assert {message, options} = changeset.errors[:seed]
      assert message == "must be greater than or equal to %{number}"
      assert options[:number] == 0
    end

    test "rejects duplicate action positions as a changeset error" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 2
               )
               |> OptimizationRuns.create()

      action = %{action_type: "patch", target_id: Ecto.UUID.generate(), cost: 1}

      assert {:ok, _first} =
               %OptimizationAction{optimization_run_id: run.id, position: 1}
               |> OptimizationAction.changeset(action)
               |> Repo.insert()

      assert {:error, %Ecto.Changeset{} = changeset} =
               %OptimizationAction{optimization_run_id: run.id, position: 1}
               |> OptimizationAction.changeset(action)
               |> Repo.insert()

      refute changeset.valid?
      assert changeset.errors[:optimization_run_id] || changeset.errors[:position]
    end
  end

  describe "Optimizations" do
    test "get_report/1 regenerates a report from saved actions and the pinned revision" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())
      credential = Graph.nodes(graph) |> List.first()

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 2
               )
               |> OptimizationRuns.create()

      assert {:ok, _completed} =
               OptimizationRuns.complete(run, %{
                 actions: [
                   %{
                     action_type: "RevokeCredential",
                     target_id: credential.id,
                     cost: 1
                   }
                 ],
                 used_budget: 1,
                 runtime_ms: 12,
                 output_graph_revision_id: graph.revision_id
               })

      report = Optimizations.get_report(run.id)

      assert report.strategy == "cvss"
      assert report.requested_budget == 2
      assert report.used_budget == 1
      assert report.runtime_ms == 12

      assert [action] = report.actions
      assert action.id == credential.id
      assert action.kind == "Credential revocation"
      assert action.label == "Revoke admin"
      assert action.cost == 1
    end

    test "get_report/1 returns nil for failed or unknown runs" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 1
               )
               |> OptimizationRuns.create()

      assert Optimizations.get_report(Ecto.UUID.generate()) == nil

      OptimizationRuns.fail(run.id)
      assert Optimizations.get_report(run.id) == nil
    end

    test "get_report/1 discards runs persisted with the retired BlockReachability action" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())
      credential = Graph.nodes(graph) |> List.first()

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 2
               )
               |> OptimizationRuns.create()

      assert {:ok, _completed} =
               OptimizationRuns.complete(run, %{
                 actions: [
                   %{action_type: "BlockReachability", target_id: credential.id, cost: 1}
                 ],
                 used_budget: 1,
                 runtime_ms: 12,
                 output_graph_revision_id: graph.revision_id
               })

      assert Optimizations.get_report(run.id) == nil
    end

    test "list_runs/1 returns completed runs for graph revisions" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())
      assert {:ok, other} = Graphs.insert(graph_with_credential())

      runs =
        for _i <- 1..2 do
          assert {:ok, run} =
                   OptimizationRun.new(
                     graph_revision_id: graph.revision_id,
                     strategy: "cvss",
                     requested_budget: 1
                   )
                   |> OptimizationRuns.create()

          run
        end

      assert {:ok, _run} =
               OptimizationRun.new(
                 graph_revision_id: other.revision_id,
                 strategy: "cvss",
                 requested_budget: 1
               )
               |> OptimizationRuns.create()

      assert [] = Optimizations.list_runs([graph.revision_id])

      for run <- runs do
        assert {:ok, _} =
                 OptimizationRuns.complete(run, %{
                   actions: [],
                   used_budget: 0,
                   runtime_ms: 1,
                   output_graph_revision_id: graph.revision_id
                 })
      end

      assert [%OptimizationRun{}, %OptimizationRun{}] =
               executions = Optimizations.list_runs([graph.revision_id])

      assert executions |> Enum.map(& &1.status) == ["completed", "completed"]
    end

    test "run/1 completes synchronously through the persistence pipeline" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      request = %RunOptimizationRequest{
        graph_revision_id: graph.revision_id,
        correlation_id: Ecto.UUID.generate(),
        optimization_params: %OptimizationParams{strategy: "cvss", budget: 2}
      }

      assert {:ok, run} = Optimizations.run(request)
      assert run.status == "completed"
      assert run.output_graph_revision_id != nil
      assert run.output_graph_revision_id != graph.revision_id
      assert run.used_budget == 0
      assert run.seed == nil
      assert run.simulation_config == nil

      assert %{status: "completed", actions: []} = OptimizationRuns.load(run.id)
    end

    test "run/1 persists the resolved seed and simulation configuration" do
      assert {:ok, graph} = Graphs.insert(graph_with_host())

      host = Enum.find(Graph.nodes(graph), &(&1.type == NetworkDefense.Nodes.Host))

      request = %RunOptimizationRequest{
        graph_revision_id: graph.revision_id,
        correlation_id: Ecto.UUID.generate(),
        optimization_params: %OptimizationParams{
          strategy: "simulation_informed",
          budget: 1,
          simulation_params: %SimulationParams{
            monte_carlo_trials: 1,
            iterations_per_run: 1,
            initial_foothold_node_id: host.id,
            seed: 42,
            generate_seed: false,
            max_attempts: 1
          }
        }
      }

      assert {:ok, run} = Optimizations.run(request)
      assert run.status == "completed"
      assert run.seed == 42

      assert run.simulation_config == %{
               "monte_carlo_trials" => 1,
               "iterations_per_run" => 1,
               "initial_foothold_node_id" => host.id,
               "max_attempts" => 1
             }
    end

    test "run/1 returns a foothold validation error without persisting a run" do
      assert {:ok, graph} = Graphs.insert(graph_with_host())

      request = %RunOptimizationRequest{
        graph_revision_id: graph.revision_id,
        correlation_id: Ecto.UUID.generate(),
        optimization_params: %OptimizationParams{
          strategy: "simulation_informed",
          budget: 1,
          simulation_params: %SimulationParams{
            monte_carlo_trials: 1,
            iterations_per_run: 1,
            initial_foothold_node_id: Ecto.UUID.generate(),
            seed: 42,
            generate_seed: false,
            max_attempts: 1
          }
        }
      }

      assert {:error, :invalid_initial_foothold} =
               Optimizations.run(request)

      assert [] =
               Repo.all(
                 from(run in OptimizationRun, where: run.graph_revision_id == ^graph.revision_id)
               )
    end

    test "run/1 returns a topology reachability error without persisting a run" do
      assert {:ok, graph} = Graphs.insert(graph_with_host())
      host = Enum.find(Graph.nodes(graph), &(&1.type == NetworkDefense.Nodes.Host))

      request = %RunOptimizationRequest{
        graph_revision_id: graph.revision_id,
        correlation_id: Ecto.UUID.generate(),
        optimization_params: %OptimizationParams{
          strategy: "topology_segmentation",
          budget: 1,
          simulation_params: %SimulationParams{
            monte_carlo_trials: 1,
            iterations_per_run: 1,
            initial_foothold_node_id: host.id,
            seed: 42,
            generate_seed: false,
            max_attempts: 1
          }
        }
      }

      assert {:error, :reachability_required} =
               Optimizations.run(request)

      assert [] =
               Repo.all(
                 from(run in OptimizationRun, where: run.graph_revision_id == ^graph.revision_id)
               )
    end

    test "run/1 rejects an unknown strategy" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      request = %RunOptimizationRequest{
        graph_revision_id: graph.revision_id,
        correlation_id: Ecto.UUID.generate(),
        optimization_params: %OptimizationParams{strategy: "bogus", budget: 1}
      }

      assert {:error, :unknown_strategy} = Optimizations.run(request)
    end
  end

  defp graph_with_credential, do: GraphFixtures.persisted_credential_graph("optimization-test")

  defp graph_with_host do
    graph = Graph.new("optimization-host-test")

    segment =
      GraphFixtures.build_node(graph, NetworkSegment, %{
        "name" => "segment"
      })

    host =
      GraphFixtures.build_node(graph, Host, %{
        "name" => "foothold"
      })

    graph
    |> Graph.add_node(segment)
    |> Graph.add_node(host)
    |> Graph.add_edge(
      Edge.new(graph.id, segment.id, host.id, %{
        type: Atom.to_string(NetworkDefense.Relationships.Contains),
        data: %{}
      })
    )
  end
end
