defmodule NetworkDefense.Optimization.OptimizationRunsTest do
  use NetworkDefense.DataCase, async: true
  use Oban.Testing, repo: NetworkDefense.Repo

  import Ecto.Query

  alias NetworkDefense.Graph.{Edge, Graph, Graphs}
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, MissionCapability, NetworkSegment, Service}

  alias NetworkDefense.Optimization.Contracts.{
    OptimizationParams,
    RunOptimizationRequest,
    SimulationSettings
  }

  alias NetworkDefense.Optimization.ExecutionConfig
  alias NetworkDefense.Optimization.OptimizationAction
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Optimization.RunIdentity
  alias NetworkDefense.Optimization.SimulationInformedStrategy
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Optimizations.OptimizationWorker
  alias NetworkDefense.Rules.ReuseCredentialRule

  describe "OptimizationRuns" do
    test "creates a run as running and completes it atomically with its actions" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())
      credential = Graph.nodes(graph) |> List.first()

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "cvss",
                 requested_budget: 2,
                 execution_config: default_execution_config()
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
                 requested_budget: 2,
                 execution_config: default_execution_config()
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
                 requested_budget: 1,
                 execution_config: default_execution_config()
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
                 requested_budget: 1,
                 execution_config: default_execution_config()
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
                 requested_budget: 1,
                 execution_config: default_execution_config()
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

    test "RTYPE-ALIAS-02: persists typed execution inputs through create, complete, and load" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      execution_config = %ExecutionConfig{
        candidate_action_types: [:patch_vulnerability],
        require_pre_attack_feasibility: true,
        initial_foothold_node_id: "host-1",
        scoring: %SimulationSettings{
          objective: :mission_then_blast_radius,
          monte_carlo_trials: 1,
          iterations_per_run: 1,
          max_attempts: 1,
          rules: [:remote_service_exploitation]
        }
      }

      assert {:ok, run} =
               OptimizationRun.new(
                 graph_revision_id: graph.revision_id,
                 strategy: "simulated_annealing",
                 requested_budget: 2,
                 seed: 42,
                 execution_config: execution_config
               )
               |> OptimizationRuns.create()

      assert run.seed == 42
      assert run.execution_config == execution_config

      assert {:ok, _completed} =
               OptimizationRuns.complete(run, %{
                 actions: [],
                 used_budget: 0,
                 runtime_ms: 1,
                 output_graph_revision_id: graph.revision_id
               })

      assert %{
               seed: 42,
               execution_config: %ExecutionConfig{
                 candidate_action_types: [:patch_vulnerability],
                 scoring: %SimulationSettings{
                   objective: :mission_then_blast_radius,
                   monte_carlo_trials: 1,
                   iterations_per_run: 1,
                   max_attempts: 1,
                   rules: [:remote_service_exploitation]
                 }
               }
             } = OptimizationRuns.load(run.id)
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
                 requested_budget: 2,
                 execution_config: default_execution_config()
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
                 requested_budget: 2,
                 execution_config: default_execution_config()
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

      assert report.strategy == :cvss
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
                 requested_budget: 1,
                 execution_config: default_execution_config()
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
                 requested_budget: 2,
                 execution_config: default_execution_config()
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
                     requested_budget: 1,
                     execution_config: default_execution_config()
                   )
                   |> OptimizationRuns.create()

          run
        end

      assert {:ok, _run} =
               OptimizationRun.new(
                 graph_revision_id: other.revision_id,
                 strategy: "cvss",
                 requested_budget: 1,
                 execution_config: default_execution_config()
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

      request = request(graph, "cvss", budget: 2, seed: 7)

      assert {:ok, run} = Optimizations.run(request)
      assert run.status == "completed"
      assert run.output_graph_revision_id != nil
      assert run.output_graph_revision_id != graph.revision_id
      assert run.used_budget == 0
      assert run.seed == 7
      assert run.execution_config.scoring == nil

      assert %{status: "completed", actions: []} = OptimizationRuns.load(run.id)
    end

    test "RTYPE-ALIAS-03: run/1 persists every effective setting of the stored run" do
      assert {:ok, graph} = Graphs.insert(graph_with_host())

      host = Enum.find(Graph.nodes(graph), &(&1.type == NetworkDefense.Nodes.Host))

      request =
        request(graph, "simulation_informed",
          seed: 42,
          candidate_action_types: [:patch_vulnerability],
          initial_foothold_node_id: host.id,
          scoring: scoring(objective: :blast_radius_only)
        )

      assert {:ok, run} = Optimizations.run(request)
      assert run.status == "completed"
      assert run.seed == 42

      assert run.execution_config == %ExecutionConfig{
               candidate_action_types: [:patch_vulnerability],
               require_pre_attack_feasibility: true,
               initial_foothold_node_id: host.id,
               scoring: %SimulationSettings{
                 objective: :blast_radius_only,
                 monte_carlo_trials: 1,
                 iterations_per_run: 1,
                 max_attempts: 1,
                 rules: [:remote_service_exploitation]
               }
             }

      assert {:ok, stored_request} = RunIdentity.stored_request(run, "stored-request")
      assert stored_request.optimization_params == request.optimization_params
    end

    test "run/1 returns a foothold validation error without persisting a run" do
      assert {:ok, graph} = Graphs.insert(graph_with_host())

      request =
        request(graph, "simulation_informed",
          seed: 42,
          initial_foothold_node_id: Ecto.UUID.generate()
        )

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

      request =
        request(graph, "topology_segmentation",
          seed: 42,
          candidate_action_types: [:block_segment_reachability],
          initial_foothold_node_id: host.id
        )

      assert {:error, :reachability_required} =
               Optimizations.run(request)

      assert [] =
               Repo.all(
                 from(run in OptimizationRun, where: run.graph_revision_id == ^graph.revision_id)
               )
    end

    test "run_reserved/2 executes one failed run from its persisted settings only" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())
      request = request(graph, "cvss", budget: 1, seed: 0)

      assert {:ok, %OptimizationRun{id: run_id}} = Optimizations.prepare(request)
      assert {:ok, %OptimizationRun{status: "failed"}} = OptimizationRuns.fail(run_id)

      assert {:ok, %OptimizationRun{status: "completed", used_budget: 0}} =
               Optimizations.run_reserved(run_id, correlation_id: "reserved-execution")

      assert {:ok, %OptimizationRun{status: "completed"}} =
               Optimizations.run_reserved(run_id, correlation_id: "repeated-execution")
    end

    test "a stored run permits only its declared defense action types" do
      assert {:ok, graph} = Graphs.insert(graph_with_defense_candidates())

      for {action_type, expected} <- [
            {"RevokeCredential", NetworkDefense.DefenseActions.RevokeCredential},
            {"PatchVulnerability", NetworkDefense.DefenseActions.PatchVulnerability}
          ] do
        request =
          request(graph, "random",
            budget: 1,
            seed: 3,
            candidate_action_types: [String.to_existing_atom(Macro.underscore(action_type))]
          )

        assert {:ok, %OptimizationRun{id: run_id}} = Optimizations.run(request)

        assert %{actions: [action]} = OptimizationRuns.load(run_id)
        assert action.action_type == action_type
        assert %^expected{} = expected_action(action)
      end
    end

    test "a stored run rewrites no scientific setting on retry" do
      assert {:ok, graph} = Graphs.insert(graph_with_defense_candidates())

      request =
        request(graph, "random", budget: 1, seed: 3, candidate_action_types: [:revoke_credential])

      assert {:ok, %OptimizationRun{id: run_id}} = Optimizations.run(request)
      stored = OptimizationRuns.load(run_id)

      assert {:ok, %OptimizationRun{id: ^run_id}} =
               Optimizations.run_reserved(run_id, correlation_id: "retry")

      assert %{execution_config: execution_config} = OptimizationRuns.load(run_id)
      assert %ExecutionConfig{} = execution_config
      assert execution_config == stored.execution_config
    end

    test "topology segmentation executes without scoring settings" do
      assert {:ok, graph} = Graphs.insert(graph_with_segment_policy())

      request =
        request(graph, "topology_segmentation",
          budget: 1,
          candidate_action_types: [:block_segment_reachability],
          initial_foothold_node_id: graph_foothold_id(graph)
        )

      assert {:ok, %OptimizationRun{status: "completed"} = run} = Optimizations.run(request)
      assert %{execution_config: %ExecutionConfig{scoring: nil}} = run

      assert %{actions: [%{action_type: "BlockSegmentReachability"}]} =
               OptimizationRuns.load(run.id)
    end

    test "RTYPE-ALIAS-03: a stored run propagates its persisted objective and rule subset to scoring" do
      assert {:ok, graph} = Graphs.insert(graph_with_host())
      host = Enum.find(Graph.nodes(graph), &(&1.type == Host))

      request =
        request(graph, "simulation_informed",
          seed: 42,
          initial_foothold_node_id: host.id,
          scoring:
            scoring(
              objective: :mission_impact_only,
              rules: [:reuse_credential_rule]
            )
        )

      assert {:ok, %OptimizationRun{} = run} = Optimizations.prepare(request)
      assert {:ok, stored_request} = RunIdentity.stored_request(run, "persisted-scoring")

      assert {:ok, strategy} =
               SimulationInformedStrategy.new(
                 Graphs.load_revision(graph.revision_id),
                 stored_request.optimization_params
               )

      assert strategy.objective == :mission_impact_only
      assert strategy.rules == [%ReuseCredentialRule{}]
      assert strategy.require_pre_attack_feasibility == true
    end

    test "a disabled feasibility policy skips the pre-attack rejection" do
      assert {:ok, graph} = Graphs.insert(graph_with_infeasible_capability())

      request = request(graph, "cvss", budget: 1, seed: 0, require_pre_attack_feasibility: false)

      assert {:ok, %OptimizationRun{status: "completed"}} = Optimizations.run(request)
    end

    test "run_async/1 completes through the same pipeline and broadcasts completion" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      request = request(graph, "cvss", budget: 2, seed: 0)

      correlation_id = request.correlation_id

      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

      assert {:ok, %OptimizationRun{id: run_id}} = Optimizations.run_async(request)

      assert [
               %{
                 args: %{"run_id" => ^run_id, "correlation_id" => ^correlation_id},
                 queue: "optimizations",
                 max_attempts: 1,
                 meta: %{"traceparent" => _}
               }
             ] = all_enqueued(worker: OptimizationWorker)

      assert :ok =
               perform_job(OptimizationWorker, %{
                 "run_id" => run_id,
                 "correlation_id" => correlation_id
               })

      assert_receive {:optimization_completed,
                      %{correlation_id: ^correlation_id, optimization_id: ^run_id}},
                     5_000

      assert %{status: "completed", actions: []} = OptimizationRuns.load(run_id)
    end

    test "RTYPE-ALIAS-04: a run without execution configuration is rejected" do
      changeset =
        OptimizationRun.changeset(%OptimizationRun{}, %{
          graph_revision_id: Ecto.UUID.generate(),
          strategy: "cvss",
          requested_budget: 1,
          seed: 0
        })

      refute changeset.valid?
      assert {"can't be blank", _options} = Keyword.fetch!(changeset.errors, :execution_config)
    end

    test "run/1 rejects an unknown strategy" do
      assert {:ok, graph} = Graphs.insert(graph_with_credential())

      request = request(graph, "bogus", budget: 1, seed: 0)

      assert {:error, :unknown_strategy} = Optimizations.run(request)
    end

    test "run/1 rejects an input scenario that is infeasible before the attack" do
      assert {:ok, graph} = Graphs.insert(graph_with_infeasible_capability())

      request = request(graph, "cvss", budget: 1, seed: 0)

      assert {:error, :infeasible_input} = Optimizations.run(request)

      assert [] =
               Repo.all(
                 from(run in OptimizationRun, where: run.graph_revision_id == ^graph.revision_id)
               )
    end
  end

  defp default_execution_config do
    %ExecutionConfig{
      candidate_action_types: [:patch_vulnerability],
      require_pre_attack_feasibility: true
    }
  end

  defp request(graph, strategy, opts) do
    strategy = if strategy == "bogus", do: strategy, else: String.to_existing_atom(strategy)

    opts =
      Keyword.validate!(opts,
        budget: 1,
        seed: 0,
        candidate_action_types: [:patch_vulnerability, :revoke_credential],
        require_pre_attack_feasibility: true,
        initial_foothold_node_id: nil,
        scoring: nil,
        correlation_id: Ecto.UUID.generate()
      )

    %RunOptimizationRequest{
      graph_revision_id: graph.revision_id,
      correlation_id: opts[:correlation_id],
      optimization_params: %OptimizationParams{
        strategy: strategy,
        budget: opts[:budget],
        seed: opts[:seed],
        candidate_action_types: opts[:candidate_action_types],
        require_pre_attack_feasibility: opts[:require_pre_attack_feasibility],
        initial_foothold_node_id: opts[:initial_foothold_node_id],
        simulation_params: opts[:scoring]
      }
    }
  end

  defp scoring(opts) do
    opts =
      Keyword.validate!(opts,
        objective: :mission_then_blast_radius,
        trials: 1,
        iterations: 1,
        max_attempts: 1,
        rules: [:remote_service_exploitation]
      )

    %SimulationSettings{
      objective: opts[:objective],
      monte_carlo_trials: opts[:trials],
      iterations_per_run: opts[:iterations],
      max_attempts: opts[:max_attempts],
      rules: opts[:rules]
    }
  end

  defp expected_action(%{action_type: "RevokeCredential"}),
    do: %NetworkDefense.DefenseActions.RevokeCredential{}

  defp expected_action(%{action_type: "PatchVulnerability"}),
    do: %NetworkDefense.DefenseActions.PatchVulnerability{}

  defp graph_with_defense_candidates do
    graph = Graph.new("optimization-action-scope")

    segment = GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "segment"})
    host = GraphFixtures.build_node(graph, Host, %{"name" => "host"})

    service =
      GraphFixtures.build_node(graph, Service, %{
        "name" => "ssh",
        "protocol" => "tcp",
        "port" => 22
      })

    vulnerability =
      GraphFixtures.build_node(graph, NetworkDefense.Nodes.Vulnerability, %{
        "identifier" => "CVE-2024-0001",
        "cvss" => cvss(),
        "exploit_probability" => 1.0
      })

    credential =
      GraphFixtures.build_node(graph, NetworkDefense.Nodes.Credential, %{
        "identifier" => "admin",
        "credential_type" => "password"
      })

    graph
    |> Graph.add_node(segment)
    |> Graph.add_node(host)
    |> Graph.add_node(service)
    |> Graph.add_node(vulnerability)
    |> Graph.add_node(credential)
    |> Graph.add_edge(
      Edge.new(graph.id, segment.id, host.id, %{
        type: Atom.to_string(NetworkDefense.Relationships.Contains),
        data: %{}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, host.id, service.id, %{
        type: Atom.to_string(NetworkDefense.Relationships.Runs),
        data: %{}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, service.id, vulnerability.id, %{
        type: Atom.to_string(NetworkDefense.Relationships.HasVulnerability),
        data: %{"required_privilege" => "none", "granted_privilege" => "user"}
      })
    )
  end

  defp graph_with_segment_policy do
    graph = Graph.new("optimization-topology")

    source_segment = GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "source"})
    target_segment = GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "target"})
    source = GraphFixtures.build_node(graph, Host, %{"name" => "source"})
    target = GraphFixtures.build_node(graph, Host, %{"name" => "target"})

    service =
      GraphFixtures.build_node(graph, Service, %{
        "name" => "ssh",
        "protocol" => "tcp",
        "port" => 22
      })

    graph
    |> Graph.add_node(source_segment)
    |> Graph.add_node(target_segment)
    |> Graph.add_node(source)
    |> Graph.add_node(target)
    |> Graph.add_node(service)
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
      Edge.new(graph.id, target.id, service.id, %{
        type: Atom.to_string(NetworkDefense.Relationships.Runs),
        data: %{}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, source_segment.id, target_segment.id, %{
        type: Atom.to_string(NetworkDefense.Relationships.SegmentReachability),
        data: %{"protocol" => "tcp"}
      })
    )
  end

  defp graph_foothold_id(graph) do
    graph
    |> Graph.nodes()
    |> Enum.find(&(&1.type == Host and &1.data.name == "source"))
    |> Map.fetch!(:id)
  end

  defp cvss do
    %{
      "attack_vector" => "network",
      "attack_complexity" => "low",
      "privileges_required" => "none",
      "user_interaction" => "none",
      "scope" => "unchanged",
      "confidentiality_impact" => "high",
      "integrity_impact" => "high",
      "availability_impact" => "high"
    }
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
