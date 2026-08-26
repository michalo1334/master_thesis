defmodule NetworkDefense.Optimization.OptimizationRunsTest do
  use NetworkDefense.DataCase, async: true
  use Oban.Testing, repo: NetworkDefense.Repo

  import Ecto.Query

  alias NetworkDefense.Evaluation.{EvaluationManifest, EvaluationRun}
  alias NetworkDefense.Graph.{Edge, Graph, Graphs}
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, MissionCapability, NetworkSegment, Service}
  alias NetworkDefense.Optimization.Contracts.{OptimizationParams, RunOptimizationRequest}
  alias NetworkDefense.Optimization.OptimizationAction
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Optimizations.OptimizationWorker
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

      assert {:error, :internal_error} =
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

    test "run_async/1 completes through the same pipeline and broadcasts completion" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      request = %RunOptimizationRequest{
        graph_revision_id: graph.revision_id,
        correlation_id: Ecto.UUID.generate(),
        optimization_params: %OptimizationParams{strategy: "cvss", budget: 2}
      }

      correlation_id = request.correlation_id

      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

      assert {:ok, _job} = Optimizations.run_async(request)

      assert [
               %{
                 args: %{"run_id" => run_id, "request" => request_params},
                 queue: "optimizations",
                 max_attempts: 1,
                 meta: %{"traceparent" => _}
               }
             ] = all_enqueued(worker: OptimizationWorker)

      assert :ok =
               perform_job(OptimizationWorker, %{
                 "run_id" => run_id,
                 "request" => request_params
               })

      assert_receive {:optimization_completed,
                      %{correlation_id: ^correlation_id, optimization_id: ^run_id}},
                     5_000

      assert %{status: "completed", actions: []} = OptimizationRuns.load(run_id)
    end

    test "optimization worker marks a running run failed when run_or_resume errors" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 1
               )
               |> OptimizationRuns.create()

      request = %RunOptimizationRequest{
        graph_revision_id: Ecto.UUID.generate(),
        correlation_id: Ecto.UUID.generate(),
        optimization_params: %OptimizationParams{strategy: "cvss", budget: 1}
      }

      assert {:error, :not_found} =
               Optimizations.run_or_resume(run.id, request)

      assert {:error, :failed} =
               perform_job(OptimizationWorker, %{
                 "run_id" => run.id,
                 "request" => RunOptimizationRequest.to_params(request)
               })

      assert %{status: "failed"} = OptimizationRuns.load(run.id)
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

    test "run/1 rejects an input scenario that is infeasible before the attack" do
      assert {:ok, graph} = Graphs.insert(graph_with_infeasible_capability())

      request = %RunOptimizationRequest{
        graph_revision_id: graph.revision_id,
        correlation_id: Ecto.UUID.generate(),
        optimization_params: %OptimizationParams{strategy: "cvss", budget: 1}
      }

      assert {:error, :infeasible_input} = Optimizations.run(request)

      assert [] =
               Repo.all(
                 from(run in OptimizationRun, where: run.graph_revision_id == ^graph.revision_id)
               )
    end
  end

  describe "evaluation plan identity" do
    test "persists the model variant for an evaluation-owned run" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())
      evaluation_run = evaluation_run(graph.revision_id)

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 evaluation_run_id: evaluation_run.id,
                 model_variant: :full,
                 strategy: "cvss",
                 requested_budget: 2,
                 selection_seed: 101
               )
               |> OptimizationRuns.create()

      assert run.model_variant == :full
      assert %{model_variant: :full} = OptimizationRuns.load(run.id)
    end

    test "requires a model variant when the run belongs to an evaluation" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())
      evaluation_run = evaluation_run(graph.revision_id)

      assert {:error, changeset} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 evaluation_run_id: evaluation_run.id,
                 strategy: "cvss",
                 requested_budget: 2,
                 selection_seed: 101
               )
               |> OptimizationRuns.create()

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:model_variant]
    end

    test "keeps plans distinct across model variants and rejects duplicates within one" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())
      evaluation_run = evaluation_run(graph.revision_id)

      base = [
        graph_revision_id: graph.revision_id,
        evaluation_run_id: evaluation_run.id,
        strategy: "cvss",
        requested_budget: 2,
        selection_seed: 101
      ]

      assert {:ok, _} =
               OptimizationRun.new(base ++ [model_variant: :full]) |> OptimizationRuns.create()

      assert {:ok, blast_only_run} =
               OptimizationRun.new(base ++ [model_variant: :blast_only_unconstrained])
               |> OptimizationRuns.create()

      assert %{rows: [["blast_only_unconstrained"]]} =
               Repo.query!("SELECT model_variant FROM optimization_runs WHERE id = $1", [
                 Ecto.UUID.dump!(blast_only_run.id)
               ])

      assert {:error, %Ecto.Changeset{} = changeset} =
               OptimizationRun.new(base ++ [model_variant: :full]) |> OptimizationRuns.create()

      assert changeset.errors[:evaluation_run_id]
    end

    test "allows a standalone run without a model variant" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 1
               )
               |> OptimizationRuns.create()

      assert run.model_variant == nil
    end
  end

  defp evaluation_run(graph_revision_id) do
    manifest =
      Repo.insert!(%EvaluationManifest{
        manifest_id: "m-#{System.unique_integer([:positive])}",
        title: "T",
        content: %{}
      })

    Repo.insert!(%EvaluationRun{
      evaluation_manifest_id: manifest.id,
      source_graph_revision_id: graph_revision_id,
      resolved_manifest: %{},
      status: "running"
    })
  end

  defp graph_with_credential, do: GraphFixtures.persisted_credential_graph("optimization-test")

  defp graph_with_infeasible_capability do
    graph = Graph.new("optimization-infeasible-test")

    source_segment =
      GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "source-segment"})

    target_segment =
      GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "target-segment"})

    source = GraphFixtures.build_node(graph, Host, %{"name" => "source"})
    target = GraphFixtures.build_node(graph, Host, %{"name" => "target"})

    api =
      GraphFixtures.build_node(graph, Service, %{
        "name" => "api",
        "protocol" => "tcp",
        "port" => 443
      })

    capability =
      GraphFixtures.build_node(graph, MissionCapability, %{
        "name" => "orders",
        "impact_weight" => 8.0,
        "min_operational_support" => 1,
        "required_flows" => [
          %{"source_segment_id" => source_segment.id, "target_service_id" => api.id}
        ]
      })

    graph
    |> Graph.add_node(source_segment)
    |> Graph.add_node(target_segment)
    |> Graph.add_node(source)
    |> Graph.add_node(target)
    |> Graph.add_node(api)
    |> Graph.add_node(capability)
    |> Graph.add_edge(
      Edge.new(graph.id, source_segment.id, source.id, %{
        type: Atom.to_string(NetworkDefense.Relationships.Contains),
        data: %{}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, target_segment.id, target.id, %{
        type: Atom.to_string(NetworkDefense.Relationships.Contains),
        data: %{}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, target.id, api.id, %{
        type: Atom.to_string(NetworkDefense.Relationships.Runs),
        data: %{}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, source.id, capability.id, %{
        type: Atom.to_string(NetworkDefense.Relationships.Supports),
        data: %{}
      })
    )
  end

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
