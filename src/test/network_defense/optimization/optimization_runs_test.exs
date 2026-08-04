defmodule NetworkDefense.Optimization.OptimizationRunsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.Credential
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Optimizations

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
  end

  defp graph_with_credential do
    graph = Graph.new("optimization-test")

    credential =
      GraphFixtures.build_node(graph, Credential, %{
        "identifier" => "admin",
        "credential_type" => "password"
      })

    Graph.add_node(graph, credential)
  end
end
