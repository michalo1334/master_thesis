defmodule NetworkDefense.Evaluation.Study.Timing.FinalReplicaSummaryTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.Study.Timing.Canonical
  alias NetworkDefense.Evaluation.Study.Timing.Canonical.MeasuredReplica
  alias NetworkDefense.Evaluation.Study.Timing.Environment
  alias NetworkDefense.Evaluation.Study.Timing.FinalReplicaSummary

  alias NetworkDefense.Evaluation.Study.Timing.FinalReplicaSummary.{
    AttackAction,
    AttackerState,
    AttackStep,
    CapabilityStatus,
    Foothold,
    Item,
    PlanAction,
    RequiredFlowStatus,
    Trial
  }

  @host_a "11111111-1111-4111-8111-111111111111"
  @host_b "22222222-2222-4222-8222-222222222222"
  @service "33333333-3333-4333-8333-333333333333"
  @vulnerability "44444444-4444-4444-8444-444444444444"
  @credential "55555555-5555-4555-8555-555555555555"
  @runs_edge "66666666-6666-4666-8666-666666666666"
  @has_vulnerability_edge "77777777-7777-4777-8777-777777777777"
  @stores_credential_edge "88888888-8888-4888-8888-888888888888"
  @segment "99999999-9999-4999-8999-999999999999"

  describe "FinalReplicaSummary.new/1" do
    test "T34-SUMMARY-01: WHEN one canonical Final output includes typed graph, plan, attack path, attacker state, capability, flow, and host evidence, THE summary constructor SHALL return the typed summary" do
      assert {:ok, %FinalReplicaSummary{} = summary} = FinalReplicaSummary.new(summary_params())

      assert {:ok, %FinalReplicaSummary{items: [item]}} =
               FinalReplicaSummary.new(summary_params())

      assert %Item{
               position: 0,
               used_budget: 3,
               selected_actions: [
                 %PlanAction{
                   position: 1,
                   action_type: "block_edge",
                   target_id: @runs_edge,
                   cost: 1
                 },
                 %PlanAction{
                   position: 2,
                   action_type: "isolate_host",
                   target_id: @host_a,
                   cost: 2
                 }
               ],
               pre_attack_capability_statuses: [
                 %CapabilityStatus{capability_id: "availability", down?: false}
               ],
               pre_attack_required_flow_statuses: [
                 %RequiredFlowStatus{
                   capability_id: "availability",
                   source_segment_id: @segment,
                   target_service_id: @service,
                   available?: true
                 }
               ],
               trials: [
                 %Trial{
                   position: 0,
                   seed: 4242,
                   initial_state: %AttackerState{footholds: [], credential_ids: []},
                   steps: [
                     %AttackStep{
                       index: 1,
                       success?: true,
                       action: %AttackAction{kind: :exploit_vulnerability}
                     },
                     %AttackStep{
                       index: 2,
                       success?: true,
                       action: %AttackAction{kind: :acquire_credential}
                     }
                   ],
                   final_state: %AttackerState{
                     footholds: [
                       %Foothold{host_id: @host_a, privilege: :user},
                       %Foothold{host_id: @host_b, privilege: :administrator}
                     ],
                     credential_ids: [@credential]
                   },
                   capability_outcomes: [
                     %CapabilityStatus{capability_id: "availability", down?: false}
                   ]
                 }
               ]
             } = item

      assert Enum.map(item.output_graph.nodes, & &1.id) ==
               [@host_a, @host_b, @service, @vulnerability, @credential, @segment]

      assert [%AttackAction{kind: :exploit_vulnerability} = exploit, %AttackAction{} = acquire] =
               Enum.map(hd(item.trials).steps, & &1.action)

      assert %AttackAction{
               kind: :acquire_credential,
               credential_id: @credential,
               host_id: @host_b,
               source_host_id: nil,
               service_id: nil,
               success_probability: nil,
               required_privilege: nil,
               granted_privilege: nil,
               supporting_edge_ids: [@stores_credential_edge]
             } = acquire

      assert %AttackAction{
               attempt_count: 1,
               source_host_id: @host_a,
               target_host_id: nil,
               service_id: @service,
               vulnerability_node_id: @vulnerability,
               credential_id: nil,
               host_id: nil,
               success_probability: 0.35,
               required_privilege: :none,
               granted_privilege: :user,
               supporting_edge_ids: [@has_vulnerability_edge]
             } = exploit

      assert {:ok, %FinalReplicaSummary{} = changed} =
               FinalReplicaSummary.new(
                 summary_params(%{
                   "pre_attack_required_flow_statuses" => [
                     flow_status("availability", @segment, @service, false)
                   ]
                 })
               )

      refute changed == summary
    end

    test "T34-SUMMARY-02: WHEN one canonical list has a duplicate, gap, or non-canonical order, THE summary constructor SHALL return :non_canonical_summary" do
      unsorted_state =
        attacker_state(
          [foothold(@host_b, "administrator"), foothold(@host_a, "user")],
          [@credential]
        )

      assert {:error, :non_canonical_summary} =
               FinalReplicaSummary.new(
                 summary_params(%{"trials" => [valid_trial(%{"final_state" => unsorted_state})]})
               )
    end

    test "T34-SUMMARY-03: WHEN selected-action costs do not equal used budget, THE summary constructor SHALL return :inconsistent_summary" do
      assert {:error, :inconsistent_summary} =
               FinalReplicaSummary.new(summary_params(%{"used_budget" => 4}))
    end

    test "T34-SUMMARY-04: WHEN the top-level item list is absent or empty, THE summary constructor SHALL return :invalid_summary" do
      assert FinalReplicaSummary.new(%{}) == {:error, :invalid_summary}
      assert FinalReplicaSummary.new(%{"items" => []}) == {:error, :invalid_summary}
    end

    test "T34-SUMMARY-05: WHEN an existing summary is revalidated, THE summary validator SHALL accept one complete summary and reject an empty item list" do
      assert {:ok, %FinalReplicaSummary{} = summary} =
               FinalReplicaSummary.validate(build_summary())

      assert summary == build_summary()

      assert FinalReplicaSummary.validate(%FinalReplicaSummary{items: []}) ==
               {:error, :invalid_summary}
    end

    test "T34-SUMMARY-06: WHEN a stored summary is structurally malformed, THE summary validator and canonical selector SHALL return tagged invalid errors without raising" do
      malformed = %FinalReplicaSummary{items: [1]}

      assert FinalReplicaSummary.validate(malformed) == {:error, :invalid_summary}

      assert FinalReplicaSummary.validate(%FinalReplicaSummary{items: :bad}) ==
               {:error, :invalid_summary}

      assert MeasuredReplica.validate(%MeasuredReplica{position: 0, summary: malformed}) ==
               {:error, :invalid_measured_replica}

      malformed_wrappers = Enum.map(0..4, &%MeasuredReplica{position: &1, summary: malformed})

      assert Canonical.select(malformed_wrappers) == {:error, :invalid_measured_replicas}
    end
  end

  describe "MeasuredReplica.new/1" do
    test "T34-CANONICAL-05: WHEN a measured wrapper nests a summary that passes shape checks but fails canonical or consistency checks, THE wrapper constructor SHALL return :invalid_measured_replica" do
      unsorted_state =
        attacker_state(
          [foothold(@host_b, "administrator"), foothold(@host_a, "user")],
          [@credential]
        )

      non_canonical =
        summary_params(%{"trials" => [valid_trial(%{"final_state" => unsorted_state})]})

      assert MeasuredReplica.new(%{"position" => 0, "summary" => non_canonical}) ==
               {:error, :invalid_measured_replica}

      assert MeasuredReplica.new(%{
               "position" => 0,
               "summary" => summary_params(%{"used_budget" => 4})
             }) ==
               {:error, :invalid_measured_replica}

      assert {:ok, %MeasuredReplica{}} =
               MeasuredReplica.new(%{"position" => 0, "summary" => summary_params()})
    end
  end

  describe "Canonical.select/1" do
    test "T34-CANONICAL-01: WHEN measured positions zero through four contain equal summaries, THE canonical selector SHALL return the summary from position zero" do
      replicas =
        [3, 0, 4, 1, 2]
        |> Enum.map(&%{"position" => &1, "summary" => summary_params()})
        |> Enum.map(&MeasuredReplica.new/1)
        |> Enum.map(fn {:ok, %MeasuredReplica{} = replica} -> replica end)

      assert Canonical.select(replicas) == {:ok, build_summary()}
    end

    test "T34-CANONICAL-02: WHEN measured positions contain a duplicate, gap, warm-up, or extra position, THE canonical selector SHALL return :invalid_measured_replicas" do
      summary = build_summary()

      invalid_position_sets = [
        {"warm-up position", [-1, 0, 1, 2, 3]},
        {"duplicate position", [0, 0, 1, 2, 3]},
        {"gap in positions", [0, 1, 2, 3]},
        {"extra position", [0, 1, 2, 3, 4, 4]}
      ]

      for {label, positions} <- invalid_position_sets do
        replicas = Enum.map(positions, &replica(&1, summary))

        assert Canonical.select(replicas) == {:error, :invalid_measured_replicas}, label
      end
    end

    test "T34-CANONICAL-03: WHEN one measured replica has a different selected action, THE canonical selector SHALL return :replica_mismatch" do
      summary = build_summary()

      assert {:ok, %FinalReplicaSummary{} = divergent} =
               FinalReplicaSummary.new(
                 summary_params(%{
                   "selected_actions" => [
                     plan_action(1, "block_edge", @runs_edge, 1),
                     plan_action(2, "isolate_host", @host_b, 2)
                   ]
                 })
               )

      replicas = [
        replica(0, summary),
        replica(1, summary),
        replica(2, divergent),
        replica(3, summary),
        replica(4, summary)
      ]

      assert Canonical.select(replicas) == {:error, :replica_mismatch}
    end

    test "T34-CANONICAL-04: WHEN a measured wrapper carries a nil, wrong-type, or inconsistent summary, THE canonical selector SHALL return :invalid_measured_replicas" do
      summary = build_summary()

      invalid_replica_sets = [
        [
          replica(0, nil),
          replica(1, summary),
          replica(2, summary),
          replica(3, summary),
          replica(4, summary)
        ],
        [
          replica(0, summary),
          replica(1, summary),
          replica(2, summary_params()),
          replica(3, summary),
          replica(4, summary)
        ],
        [
          replica(0, summary),
          replica(1, summary),
          replica(2, summary),
          replica(3, misaligned_budget_summary()),
          replica(4, summary)
        ]
      ]

      for replicas <- invalid_replica_sets do
        assert Canonical.select(replicas) == {:error, :invalid_measured_replicas}
      end
    end
  end

  describe "Environment.matches/2" do
    test "T34-ENVIRONMENT-01: WHEN declared and observed non-blank environment revisions are equal, THE environment comparator SHALL return success" do
      assert Environment.matches("revision-1", "revision-1") == :ok
    end

    test "T34-ENVIRONMENT-02: WHEN either environment revision is missing or blank, THE environment comparator SHALL return :missing_environment" do
      for {declared, observed} <- [
            {nil, "revision-1"},
            {"revision-1", nil},
            {"", "revision-1"},
            {"revision-1", "   "},
            {nil, nil}
          ] do
        assert Environment.matches(declared, observed) == {:error, :missing_environment}
      end
    end

    test "T34-ENVIRONMENT-03: WHEN declared and observed environment revisions differ, THE environment comparator SHALL return :environment_mismatch" do
      assert Environment.matches("revision-1", "revision-2") == {:error, :environment_mismatch}
    end
  end

  defp build_summary do
    {:ok, summary} = FinalReplicaSummary.new(summary_params())
    summary
  end

  defp replica(position, summary), do: %MeasuredReplica{position: position, summary: summary}

  defp misaligned_budget_summary do
    %FinalReplicaSummary{items: [item]} = build_summary()
    %FinalReplicaSummary{items: [%{item | used_budget: item.used_budget + 1}]}
  end

  defp summary_params(item_overrides \\ %{}) do
    %{"items" => [valid_item(item_overrides)]}
  end

  defp valid_item(overrides) do
    Map.merge(
      %{
        "position" => 0,
        "used_budget" => 3,
        "selected_actions" => [
          plan_action(1, "block_edge", @runs_edge, 1),
          plan_action(2, "isolate_host", @host_a, 2)
        ],
        "output_graph" => graph(),
        "pre_attack_capability_statuses" => [capability_status("availability", false)],
        "pre_attack_required_flow_statuses" => [
          flow_status("availability", @segment, @service, true)
        ],
        "trials" => [valid_trial(%{})]
      },
      overrides
    )
  end

  defp valid_trial(overrides) do
    Map.merge(
      %{
        "position" => 0,
        "seed" => 4242,
        "initial_state" => attacker_state([], []),
        "steps" => [
          %{
            "index" => 1,
            "success?" => true,
            "action" => %{
              "kind" => "exploit_vulnerability",
              "attempt_count" => 1,
              "source_host_id" => @host_a,
              "target_host_id" => nil,
              "service_id" => @service,
              "vulnerability_node_id" => @vulnerability,
              "success_probability" => 0.35,
              "required_privilege" => "none",
              "granted_privilege" => "user",
              "supporting_edge_ids" => [@has_vulnerability_edge]
            }
          },
          %{
            "index" => 2,
            "success?" => true,
            "action" => %{
              "kind" => "acquire_credential",
              "attempt_count" => 1,
              "credential_id" => @credential,
              "host_id" => @host_b,
              "supporting_edge_ids" => [@stores_credential_edge]
            }
          }
        ],
        "final_state" =>
          attacker_state(
            [foothold(@host_a, "user"), foothold(@host_b, "administrator")],
            [@credential]
          ),
        "capability_outcomes" => [capability_status("availability", false)]
      },
      overrides
    )
  end

  defp attacker_state(footholds, credential_ids) do
    %{"footholds" => footholds, "credential_ids" => credential_ids}
  end

  defp foothold(host_id, privilege) do
    %{"host_id" => host_id, "privilege" => privilege}
  end

  defp capability_status(capability_id, down?) do
    %{"capability_id" => capability_id, "down?" => down?}
  end

  defp flow_status(capability_id, source_segment_id, target_service_id, available?) do
    %{
      "capability_id" => capability_id,
      "source_segment_id" => source_segment_id,
      "target_service_id" => target_service_id,
      "available?" => available?
    }
  end

  defp plan_action(position, action_type, target_id, cost) do
    %{
      "position" => position,
      "action_type" => action_type,
      "target_id" => target_id,
      "cost" => cost
    }
  end

  defp graph do
    %{
      "nodes" => [
        node(@host_a, "Host", %{"name" => "gateway"}),
        node(@host_b, "Host", %{"name" => "database"}),
        node(@service, "Service", %{"name" => "ssh", "protocol" => "tcp", "port" => 22}),
        node(@vulnerability, "Vulnerability", %{
          "identifier" => "CVE-2024-0001",
          "exploit_probability" => 0.35,
          "cvss" => cvss()
        }),
        node(@credential, "Credential", %{
          "identifier" => "db-root",
          "credential_type" => "password"
        }),
        node(@segment, "NetworkSegment", %{"name" => "dmz", "cidr" => "10.0.0.0/24"})
      ],
      "edges" => [
        edge(@runs_edge, @host_b, @service, "Runs", %{}),
        edge(@has_vulnerability_edge, @service, @vulnerability, "HasVulnerability", %{
          "required_privilege" => "none",
          "granted_privilege" => "user"
        }),
        edge(@stores_credential_edge, @host_b, @credential, "StoresCredential", %{
          "required_privilege" => "user"
        })
      ]
    }
  end

  defp node(id, type, data) do
    %{
      "id" => id,
      "type" => type,
      "data" => data,
      "view_data" => %{"x_pos" => 0.0, "y_pos" => 0.0, "radius" => nil}
    }
  end

  defp edge(id, from_id, to_id, type, data) do
    %{"id" => id, "from_id" => from_id, "to_id" => to_id, "type" => type, "data" => data}
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
end
