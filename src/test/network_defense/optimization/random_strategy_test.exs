defmodule NetworkDefense.Optimization.RandomStrategyTest do
  use ExUnit.Case, async: true

  @moduletag :unit
  @moduletag case_id:
               "RAND-01/RAND-02/RAND-03/RAND-04/RAND-05/RAND-06/RAND-07/RAND-08/RAND-09/RAND-10/RAND-11/RAND-12/RAND-13/DUP-01"

  alias NetworkDefense.DefenseActions.{BlockSegmentReachability, DefenseAction, RevokeCredential}
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Credential, Host, NetworkSegment, Service}
  alias NetworkDefense.Optimization.Contracts.OptimizationParams
  alias NetworkDefense.Optimization.{Optimizer, RandomStrategy, SimulationStrategy, Strategy}
  alias NetworkDefense.Relationships.{AuthenticatesTo, Contains, Runs, SegmentReachability}

  # Fixed seed enumeration keeps the ordering assertions deterministic.
  @seeds Enum.to_list(1..12)

  describe "rank/4 candidate eligibility" do
    # RAND-01
    # Requirement: WHEN several useful candidates exist, THE random strategy
    # SHALL return every useful candidate exactly once.
    test "returns a full permutation of useful candidates" do
      graph = credential_graph(["credential-a", "credential-b", "credential-c"])

      expected = ["credential-a", "credential-b", "credential-c"]

      for seed <- @seeds do
        ranked = Strategy.rank(%RandomStrategy{seed: seed}, [RevokeCredential], graph, 3)

        assert Enum.sort(credential_ids(ranked)) == expected
      end
    end

    # RAND-02
    # Requirement: WHEN a single eligible policy edge exists, THE random
    # strategy SHALL return exactly that action.
    test "returns the only eligible policy edge" do
      graph = policy_graph()

      assert [%BlockSegmentReachability{edge_id: "policy-ab"}] =
               Strategy.rank(%RandomStrategy{seed: 0}, [BlockSegmentReachability], graph, 1)
    end

    # RAND-03
    # Requirement: WHEN the remaining budget changes and the candidate set stays
    # the same, THE random strategy SHALL derive a fresh selection order.
    test "derives a fresh order for a different remaining budget" do
      graph = credential_graph(["credential-a", "credential-b"])

      orders =
        for budget <- [2, 3] do
          for seed <- @seeds,
              do:
                Strategy.rank(%RandomStrategy{seed: seed}, [RevokeCredential], graph, budget)
                |> credential_ids()
        end

      [at_budget_two, at_budget_three] = orders

      assert Enum.zip(at_budget_two, at_budget_three)
             |> Enum.any?(fn {two, three} -> two != three end)
    end

    # RAND-04
    # Requirement: WHEN candidates have a natural enumeration order, THE random
    # strategy SHALL produce a nontrivial order for part of the fixed seed set.
    test "produces a nontrivial permutation" do
      graph = credential_graph(["credential-a", "credential-b", "credential-c"])
      enumeration_order = ["credential-a", "credential-b", "credential-c"]

      orders =
        for seed <- @seeds do
          Strategy.rank(%RandomStrategy{seed: seed}, [RevokeCredential], graph, 3)
          |> credential_ids()
        end

      assert Enum.all?(orders, &(Enum.sort(&1) == enumeration_order))
      assert Enum.any?(orders, &(&1 != enumeration_order))
    end

    # RAND-05
    # Requirement: WHEN rank runs twice with the same seed and budget, THE random
    # strategy SHALL return the same plan and SHALL leave the process-global
    # random state unchanged.
    test "replays the same plan without touching process-global randomness" do
      graph = credential_graph(["credential-a", "credential-b"])
      strategy = %RandomStrategy{seed: 1234}

      :rand.seed(:exsss, {11, 22, 33})
      expected_next_global_value = :rand.uniform(1_000_000)

      :rand.seed(:exsss, {11, 22, 33})

      first = Strategy.rank(strategy, [RevokeCredential], graph, 2)
      second = Strategy.rank(strategy, [RevokeCredential], graph, 2)

      assert first == second
      assert :rand.uniform(1_000_000) == expected_next_global_value
    end

    # RAND-06
    # Requirement: WHEN a credential has no outgoing AuthenticatesTo edge, THE
    # random strategy SHALL exclude that credential from selection.
    test "excludes a credential without an AuthenticatesTo edge" do
      orphan = node("credential-orphan", Credential, credential_data("credential-orphan"))

      graph =
        credential_graph(["credential-a"])
        |> Graph.add_node(orphan)

      for seed <- @seeds do
        ranked = Strategy.rank(%RandomStrategy{seed: seed}, [RevokeCredential], graph, 2)

        assert credential_ids(ranked) == ["credential-a"]
      end
    end

    # RAND-07
    # Requirement: WHEN a credential was already revoked, THE random strategy
    # SHALL NOT offer that credential again.
    test "excludes a credential whose authentication edges are already removed" do
      graph = credential_graph(["credential-a", "credential-b"])
      revoked = DefenseAction.apply(%RevokeCredential{credential_id: "credential-a"}, graph)

      for seed <- @seeds do
        ranked = Strategy.rank(%RandomStrategy{seed: seed}, [RevokeCredential], revoked, 2)

        assert credential_ids(ranked) == ["credential-b"]
      end
    end

    # RAND-08
    # Requirement: WHEN the same revocation is applied twice, THE second
    # application SHALL leave the graph unchanged.
    test "keeps revocation application idempotent" do
      graph = credential_graph(["credential-a", "credential-b"])
      action = %RevokeCredential{credential_id: "credential-a"}

      once = DefenseAction.apply(action, graph)
      twice = DefenseAction.apply(action, once)

      assert twice == once
    end

    # RAND-09
    # Requirement: WHEN no eligible target exists, THE random strategy SHALL
    # return no action.
    test "returns no action when no eligible target exists" do
      graph = graph([node("host", Host, %{"name" => "host"})], [])

      assert Strategy.rank(%RandomStrategy{seed: 0}, [BlockSegmentReachability], graph, 1) == []
    end

    # RAND-10
    # Requirement: WHEN no action type is provided, THE random strategy SHALL
    # return no action.
    test "returns no action when no action type is provided" do
      assert Strategy.rank(%RandomStrategy{seed: 0}, [], graph([], []), 1) == []
    end
  end

  describe "optimizer budget use" do
    # RAND-11
    # Requirement: WHEN the budget covers two useful credential revocations, THE
    # optimizer SHALL apply both revocations.
    test "revokes both useful credentials within a budget of two" do
      graph = credential_graph(["credential-a", "credential-b"])

      result =
        Optimizer.apply(graph, %RandomStrategy{seed: 1}, 2,
          action_types: [RevokeCredential],
          require_pre_attack_feasibility: false
        )

      assert result.actions |> credential_ids() |> Enum.sort() ==
               ["credential-a", "credential-b"]

      assert result.budget_used == 2
      assert authenticates_to_edges(result.graph) == []
    end

    # RAND-12
    # Requirement: WHEN the budget exceeds the useful action count, THE optimizer
    # SHALL stop after the last useful action.
    test "stops after the second action when the budget is three" do
      graph = credential_graph(["credential-a", "credential-b"])

      result =
        Optimizer.apply(graph, %RandomStrategy{seed: 1}, 3,
          action_types: [RevokeCredential],
          require_pre_attack_feasibility: false
        )

      assert result.actions |> credential_ids() |> Enum.sort() ==
               ["credential-a", "credential-b"]

      assert result.budget_used == 2
      assert authenticates_to_edges(result.graph) == []
    end

    # RAND-13
    # Requirement: WHEN no candidate changes the graph, THE optimizer SHALL use
    # no budget and return no action.
    test "uses no budget when no credential authenticates anywhere" do
      host = node("host", Host, %{"name" => "host"})
      service = node("service", Service, service_data())
      orphan = node("credential-orphan", Credential, credential_data("credential-orphan"))

      graph = graph([host, service, orphan], [edge("runs", host, service, Runs, %{})])

      result =
        Optimizer.apply(graph, %RandomStrategy{seed: 1}, 2,
          action_types: [RevokeCredential],
          require_pre_attack_feasibility: false
        )

      assert result.actions == []
      assert result.budget_used == 0
    end
  end

  describe "duplicate declared action types" do
    # DUP-01
    # Requirement: WHEN the declared candidate action types repeat an entry, THE
    # contract SHALL accept the list, THE candidate helper and the random strategy
    # SHALL rank every unique action once, and THE optimizer SHALL apply distinct
    # targets.
    test "ranks each unique action once" do
      graph = duplicate_type_graph()
      duplicated_types = [:revoke_credential, :revoke_credential, :block_segment_reachability]
      action_types = [RevokeCredential, RevokeCredential, BlockSegmentReachability]

      assert {:ok, params} =
               OptimizationParams.validate(%{
                 "strategy" => "random",
                 "budget" => 2,
                 "seed" => 0,
                 "candidate_action_types" => Enum.map(duplicated_types, &Atom.to_string/1),
                 "require_pre_attack_feasibility" => false
               })

      assert params.candidate_action_types == duplicated_types

      candidates = SimulationStrategy.candidate_actions(action_types, graph)

      assert [_, _, _] = candidates
      assert [_, _, _] = Enum.uniq(Enum.map(candidates, &defense_target/1))

      ranked = Strategy.rank(%RandomStrategy{seed: 1}, action_types, graph, 2)

      assert [_, _, _] = ranked
      assert [_, _, _] = Enum.uniq(Enum.map(ranked, &defense_target/1))

      result =
        Optimizer.apply(graph, %RandomStrategy{seed: 1}, 2,
          action_types: action_types,
          require_pre_attack_feasibility: false
        )

      applied_targets = Enum.map(result.actions, &defense_target/1)

      assert [_, _] = applied_targets
      assert [_, _] = Enum.uniq(applied_targets)
      assert result.budget_used == 2
    end
  end

  defp policy_graph do
    segment_a = node("segment-a", NetworkSegment, %{"name" => "segment-a"})
    segment_b = node("segment-b", NetworkSegment, %{"name" => "segment-b"})
    host_a = node("host-a", Host, %{"name" => "host-a"})
    host_b = node("host-b", Host, %{"name" => "host-b"})
    service = node("service", Service, service_data())

    graph(
      [segment_a, segment_b, host_a, host_b, service],
      [
        edge("contains-a", segment_a, host_a, Contains, %{}),
        edge("contains-b", segment_b, host_b, Contains, %{}),
        edge("runs-b", host_b, service, Runs, %{}),
        edge("policy-ab", segment_a, segment_b, SegmentReachability, %{"protocol" => "tcp"})
      ]
    )
  end

  defp credential_graph(identifiers) do
    host = node("host", Host, %{"name" => "host"})
    service = node("service", Service, service_data())

    credentials =
      Enum.map(identifiers, &node(&1, Credential, credential_data(&1)))

    authentication_edges =
      Enum.map(credentials, fn credential ->
        edge(
          "auth-" <> credential.id,
          credential,
          service,
          AuthenticatesTo,
          %{"granted_privilege" => "user"}
        )
      end)

    graph(
      [host, service | credentials],
      [edge("runs", host, service, Runs, %{}) | authentication_edges]
    )
  end

  defp duplicate_type_graph do
    segment_a = node("segment-a", NetworkSegment, %{"name" => "segment-a"})
    segment_b = node("segment-b", NetworkSegment, %{"name" => "segment-b"})
    host = node("host", Host, %{"name" => "host"})
    service = node("service", Service, service_data())
    credential_a = node("credential-a", Credential, credential_data("credential-a"))
    credential_b = node("credential-b", Credential, credential_data("credential-b"))

    graph(
      [segment_a, segment_b, host, service, credential_a, credential_b],
      [
        edge("policy-ab", segment_a, segment_b, SegmentReachability, %{"protocol" => "tcp"}),
        edge("runs", host, service, Runs, %{}),
        edge("auth-a", credential_a, service, AuthenticatesTo, %{"granted_privilege" => "user"}),
        edge("auth-b", credential_b, service, AuthenticatesTo, %{"granted_privilege" => "user"})
      ]
    )
  end

  defp defense_target(action), do: DefenseAction.target(action)

  defp credential_ids(actions), do: Enum.map(actions, & &1.credential_id)

  defp authenticates_to_edges(graph) do
    graph
    |> Graph.edges()
    |> Enum.filter(&(&1.type == AuthenticatesTo))
  end

  defp graph(nodes, edges), do: GraphFixtures.graph(nodes, edges)

  defp node(id, type, data), do: GraphFixtures.node(id, type, data)

  defp edge(id, from, to, type, data), do: GraphFixtures.edge(id, from, to, type, data)

  defp service_data, do: %{"name" => "service", "protocol" => "tcp", "port" => 443}

  defp credential_data(identifier),
    do: %{"identifier" => identifier, "credential_type" => "password"}
end
