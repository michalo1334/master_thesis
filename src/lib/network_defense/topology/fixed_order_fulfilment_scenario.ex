defmodule NetworkDefense.Topology.FixedOrderFulfilmentScenario do
  @moduledoc "Builds the fixed order-fulfilment graph and calibrated evaluation manifests."

  alias NetworkDefense.Graph.{Edge, Graph, Node}

  alias NetworkDefense.Nodes.{
    Credential,
    Host,
    MissionCapability,
    NetworkSegment,
    Service,
    Vulnerability
  }

  alias NetworkDefense.Optimization.{ModelVariant, SimulationObjective}

  @title "Fixed order fulfilment scenario"
  @manifest_id "fixed-order-fulfilment-v1"
  @feasibility_manifest_id "fixed-order-fulfilment-feasibility-v1"
  @feasibility_manifest_title "Fixed order fulfilment feasibility scenario"

  alias NetworkDefense.Relationships.{
    AuthenticatesTo,
    Contains,
    HasVulnerability,
    Runs,
    SegmentReachability,
    StoresCredential,
    Supports
  }

  @segments [
    {:external, "External", 0},
    {:public_dmz, "Public DMZ", 100},
    {:partner_dmz, "Partner DMZ", 200},
    {:application, "Application", 300},
    {:data, "Data", 400},
    {:identity, "Identity", 500},
    {:management, "Management", 600},
    {:user, "User", 700},
    {:monitoring, "Monitoring", 800},
    {:backup, "Backup", 900}
  ]

  @hosts [
    {:external, ["internet-entry"]},
    {:public_dmz, ["order-gateway", "catalog-gateway", "public-status"]},
    {:partner_dmz, ["vendor-portal", "partner-access-gateway", "partner-mail-relay"]},
    {:application,
     [
       "order-service",
       "inventory-service",
       "payment-service",
       "customer-support-service",
       "integration-service",
       "reporting-service",
       "admin-service",
       "fulfilment-service",
       "pricing-service",
       "notification-service",
       "returns-service",
       "warehouse-service"
     ]},
    {:data,
     [
       "order-database",
       "inventory-database",
       "customer-database",
       "payment-database",
       "reporting-database",
       "file-store",
       "cache-store",
       "search-index"
     ]},
    {:identity,
     [
       "directory-service",
       "federation-service",
       "certificate-service",
       "dns-service",
       "identity-proxy"
     ]},
    {:management,
     [
       "operations-bastion",
       "platform-bastion",
       "configuration-service",
       "virtualization-manager",
       "patch-service",
       "asset-service"
     ]},
    {:user,
     [
       "sales-01",
       "sales-02",
       "sales-03",
       "sales-04",
       "sales-05",
       "sales-06",
       "sales-07",
       "sales-08",
       "customer-care-01",
       "customer-care-02",
       "customer-care-03",
       "customer-care-04",
       "customer-care-05",
       "customer-care-06",
       "warehouse-01",
       "warehouse-02",
       "warehouse-03",
       "warehouse-04",
       "warehouse-05",
       "warehouse-06",
       "warehouse-07",
       "warehouse-08",
       "finance-01",
       "finance-02",
       "finance-03",
       "finance-04",
       "finance-05",
       "engineering-01",
       "engineering-02",
       "engineering-03",
       "engineering-04",
       "engineering-05",
       "engineering-06",
       "engineering-07"
     ]},
    {:monitoring, ["log-collector", "security-analytics", "metrics-service", "alert-manager"]},
    {:backup, ["backup-controller", "backup-repository", "recovery-manager", "archive-service"]}
  ]

  @services [
    {"order-gateway", "https", :tcp, 443},
    {"catalog-gateway", "https", :tcp, 443},
    {"public-status", "https", :tcp, 443},
    {"vendor-portal", "https", :tcp, 443},
    {"partner-access-gateway", "https", :tcp, 443},
    {"partner-mail-relay", "smtp", :tcp, 25},
    {"order-service", "order-api", :tcp, 8080},
    {"order-service", "ssh", :tcp, 22},
    {"order-service", "backup-agent", :tcp, 10_000},
    {"integration-service", "partner-api", :tcp, 8443},
    {"order-database", "postgresql", :tcp, 5432},
    {"order-database", "ssh", :tcp, 22},
    {"order-database", "backup-agent", :tcp, 10_000},
    {"inventory-database", "postgresql", :tcp, 5432},
    {"directory-service", "ldap", :tcp, 389},
    {"directory-service", "ssh", :tcp, 22},
    {"operations-bastion", "ssh", :tcp, 22},
    {"log-collector", "syslog", :tcp, 6514},
    {"backup-controller", "backup", :tcp, 10_000}
  ]

  @vulnerabilities [
    %{
      identifier: "CVE-2021-44228",
      host: "partner-access-gateway",
      service: "https",
      product: "Apache Log4j",
      version: "2.14.1",
      cpe: "cpe:2.3:a:apache:log4j:2.14.1:*:*:*:*:*:*:*",
      cvss_vector: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H",
      cvss_base_score: 10.0,
      cvss: %{
        "attack_vector" => "network",
        "attack_complexity" => "low",
        "privileges_required" => "none",
        "user_interaction" => "none",
        "scope" => "changed",
        "confidentiality_impact" => "high",
        "integrity_impact" => "high",
        "availability_impact" => "high"
      },
      exploit_probability: 0.9
    },
    %{
      identifier: "CVE-2021-42013",
      host: "vendor-portal",
      service: "https",
      product: "Apache HTTP Server",
      version: "2.4.50",
      cpe: "cpe:2.3:a:apache:http_server:2.4.50:*:*:*:*:*:*:*",
      cvss_vector: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H",
      cvss_base_score: 9.8,
      cvss: %{
        "attack_vector" => "network",
        "attack_complexity" => "low",
        "privileges_required" => "none",
        "user_interaction" => "none",
        "scope" => "unchanged",
        "confidentiality_impact" => "high",
        "integrity_impact" => "high",
        "availability_impact" => "high"
      },
      exploit_probability: 0.6
    },
    %{
      identifier: "CVE-2017-9805",
      host: "order-gateway",
      service: "https",
      product: "Apache Struts",
      version: "2.5.12",
      cpe: "cpe:2.3:a:apache:struts:2.5.12:*:*:*:*:*:*:*",
      cvss_vector: "CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:H",
      cvss_base_score: 8.1,
      cvss: %{
        "attack_vector" => "network",
        "attack_complexity" => "high",
        "privileges_required" => "none",
        "user_interaction" => "none",
        "scope" => "unchanged",
        "confidentiality_impact" => "high",
        "integrity_impact" => "high",
        "availability_impact" => "high"
      },
      exploit_probability: 0.5
    }
  ]

  @policies [
    {:external, :public_dmz, :tcp, 443},
    {:external, :partner_dmz, :tcp, 443},
    {:public_dmz, :application, :tcp, 8080},
    {:partner_dmz, :application, :tcp, 8443},
    {:application, :data, :tcp, 5432},
    {:user, :identity, :tcp, 389},
    {:management, :application, :tcp, 22},
    {:management, :data, :tcp, 22},
    {:management, :identity, :tcp, 22},
    {:application, :monitoring, :tcp, 6514},
    {:data, :monitoring, :tcp, 6514},
    {:backup, :application, :tcp, 10_000},
    {:backup, :data, :tcp, 10_000}
  ]

  def title, do: @title

  def manifest_id, do: @manifest_id

  def feasibility_manifest_id, do: @feasibility_manifest_id

  def feasibility_manifest_title, do: @feasibility_manifest_title

  def vulnerabilities, do: @vulnerabilities

  def graph do
    graph = Graph.new(@title)
    {graph, segment_ids} = add_segments(graph)
    {graph, host_ids} = add_hosts(graph, segment_ids)
    {graph, service_ids} = add_services(graph, host_ids)

    graph
    |> add_policies(segment_ids)
    |> add_vulnerabilities(service_ids)
    |> add_credential(host_ids, service_ids)
    |> add_mission_capabilities(segment_ids, host_ids, service_ids)
  end

  @doc """
  Builds the local evaluation manifest content for the persisted revision and
  entry host. The content is schema-version 3 and is the calibrated Phase 1
  pilot configuration. It is not future calibration input. The severity/mission
  manifest contrasts simulation-informed full patching against CVSS priority.
  """
  @spec manifest_content(String.t(), String.t()) :: map()
  def manifest_content(graph_revision_id, entry_host_id) do
    %{
      "schema_version" => 3,
      "model_version" => "current-model-version",
      "id" => @manifest_id,
      "source" => %{"type" => "graph_revision", "graph_revision_id" => graph_revision_id},
      "attacker" => %{
        "entry_host" => %{"type" => "node_id", "value" => entry_host_id},
        "max_attempts" => 1
      },
      "model_variants" => canonical_variants([:full]),
      "strategy_runs" => [
        %{
          "model_variant" => "full",
          "strategy" => "null",
          "budget" => 1,
          "selection_seeds" => [101]
        },
        %{
          "model_variant" => "full",
          "strategy" => "cvss",
          "budget" => 1,
          "selection_seeds" => [102]
        },
        %{
          "model_variant" => "full",
          "strategy" => "simulation_informed",
          "budget" => 1,
          "selection_seeds" => [201]
        }
      ],
      "analysis" =>
        analysis(%{
          "strategy" => "simulation_informed",
          "model_variant" => "full",
          "baseline" => "cvss",
          "baseline_model_variant" => "full",
          "budget" => 1,
          "outcome" => "blast_radius"
        }),
      "evaluation" => evaluation()
    }
  end

  @doc """
  Builds the feasibility manifest content for the same revision and its
  dedicated public order-gateway entry host. It contrasts a
  pre-attack-feasibility-constrained blast-only defender against an
  unconstrained one and is not future calibration input.
  """
  @spec feasibility_manifest_content(String.t(), String.t()) :: map()
  def feasibility_manifest_content(graph_revision_id, entry_host_id) do
    %{
      "schema_version" => 3,
      "model_version" => "current-model-version",
      "id" => @feasibility_manifest_id,
      "source" => %{"type" => "graph_revision", "graph_revision_id" => graph_revision_id},
      "attacker" => %{
        "entry_host" => %{"type" => "node_id", "value" => entry_host_id},
        "max_attempts" => 1
      },
      "model_variants" => canonical_variants([:blast_only, :blast_only_unconstrained]),
      "strategy_runs" => [
        %{
          "model_variant" => "blast_only",
          "strategy" => "simulation_informed",
          "budget" => 1,
          "selection_seeds" => [401]
        },
        %{
          "model_variant" => "blast_only_unconstrained",
          "strategy" => "simulation_informed",
          "budget" => 1,
          "selection_seeds" => [401]
        }
      ],
      "analysis" =>
        analysis(%{
          "strategy" => "simulation_informed",
          "model_variant" => "blast_only_unconstrained",
          "baseline" => "simulation_informed",
          "baseline_model_variant" => "blast_only",
          "budget" => 1,
          "outcome" => "blast_radius"
        }),
      "evaluation" => evaluation()
    }
  end

  defp analysis(comparison) do
    %{
      "primary_comparisons" => [comparison],
      "confidence_level" => 0.95,
      "bootstrap_resamples" => 100,
      "permutation_resamples" => 100,
      "multiplicity_correction" => "holm",
      "seed" => 9001,
      "pilot" => %{"ci_half_width" => 0.25}
    }
  end

  defp evaluation do
    %{
      "trials" => 10,
      "seed" => 9001,
      "optimizer_trials" => 20,
      "optimizer_iterations" => 5
    }
  end

  defp canonical_variants(keys) do
    Enum.map(keys, fn key ->
      definition = ModelVariant.definition(key)

      %{
        "id" => ModelVariant.to_wire(key),
        "objective" => SimulationObjective.to_wire(definition.objective),
        "require_pre_attack_feasibility" => definition.require_pre_attack_feasibility
      }
    end)
  end

  defp add_segments(graph) do
    Enum.reduce(@segments, {graph, %{}}, fn {key, name, x_pos}, {graph, segment_ids} ->
      segment =
        Node.new(graph.id, %{
          type: Atom.to_string(NetworkSegment),
          data: %{"name" => name},
          view_data: %{"x_pos" => x_pos, "y_pos" => 0}
        })

      {Graph.add_node(graph, segment), Map.put(segment_ids, key, segment.id)}
    end)
  end

  defp add_hosts(graph, segment_ids) do
    Enum.reduce(@hosts, {graph, %{}}, fn {segment, names}, {graph, host_ids} ->
      Enum.with_index(names, 1)
      |> Enum.reduce({graph, host_ids}, fn {name, index}, {graph, host_ids} ->
        host =
          Node.new(graph.id, %{
            type: Atom.to_string(Host),
            data: %{"name" => name},
            view_data: %{"x_pos" => segment_x(segment) + 40, "y_pos" => index * 50}
          })

        graph = Graph.add_node(graph, host)

        graph =
          Graph.add_edge(
            graph,
            Edge.new(graph.id, Map.fetch!(segment_ids, segment), host.id, %{
              type: Atom.to_string(Contains),
              data: %{}
            })
          )

        {graph, Map.put(host_ids, name, host.id)}
      end)
    end)
  end

  defp add_services(graph, host_ids) do
    Enum.reduce(@services, {graph, %{}}, fn {host_name, name, protocol, port},
                                            {graph, service_ids} ->
      data = %{"name" => name, "protocol" => Atom.to_string(protocol), "port" => port}

      data =
        case service_version(host_name, name) do
          nil -> data
          version -> Map.put(data, "version", version)
        end

      service =
        Node.new(graph.id, %{
          type: Atom.to_string(Service),
          data: data,
          view_data: %{"x_pos" => 1_000, "y_pos" => port}
        })

      graph =
        graph
        |> Graph.add_node(service)
        |> Graph.add_edge(
          Edge.new(graph.id, Map.fetch!(host_ids, host_name), service.id, %{
            type: Atom.to_string(Runs),
            data: %{}
          })
        )

      {graph, Map.put(service_ids, {host_name, name}, service.id)}
    end)
  end

  defp add_policies(graph, segment_ids) do
    Enum.reduce(@policies, graph, fn {source, target, protocol, port}, graph ->
      Graph.add_edge(
        graph,
        Edge.new(graph.id, Map.fetch!(segment_ids, source), Map.fetch!(segment_ids, target), %{
          type: Atom.to_string(SegmentReachability),
          data: %{
            "protocol" => Atom.to_string(protocol),
            "port_start" => port,
            "port_end" => port
          }
        })
      )
    end)
  end

  defp add_vulnerabilities(graph, service_ids) do
    Enum.reduce(@vulnerabilities, graph, fn vulnerability, graph ->
      node =
        Node.new(graph.id, %{
          type: Atom.to_string(Vulnerability),
          data: %{
            "identifier" => vulnerability.identifier,
            "cvss" => vulnerability.cvss,
            "exploit_probability" => vulnerability.exploit_probability
          },
          view_data: %{"x_pos" => 1_100, "y_pos" => 443}
        })

      graph
      |> Graph.add_node(node)
      |> Graph.add_edge(
        Edge.new(
          graph.id,
          Map.fetch!(service_ids, {vulnerability.host, vulnerability.service}),
          node.id,
          %{
            type: Atom.to_string(HasVulnerability),
            data: %{"required_privilege" => "none", "granted_privilege" => "user"}
          }
        )
      )
    end)
  end

  defp add_credential(graph, host_ids, service_ids) do
    ["order-service-deployment-key", "order-service-break-glass-key"]
    |> Enum.reduce(graph, fn identifier, graph ->
      credential =
        Node.new(graph.id, %{
          type: Atom.to_string(Credential),
          data: %{"identifier" => identifier, "credential_type" => "ssh_key"},
          view_data: %{"x_pos" => 1_100, "y_pos" => 22}
        })

      graph
      |> Graph.add_node(credential)
      |> Graph.add_edge(
        Edge.new(graph.id, Map.fetch!(host_ids, "order-gateway"), credential.id, %{
          type: Atom.to_string(StoresCredential),
          data: %{"required_privilege" => "user"}
        })
      )
      |> Graph.add_edge(
        Edge.new(
          graph.id,
          credential.id,
          Map.fetch!(service_ids, {"order-service", "order-api"}),
          %{
            type: Atom.to_string(AuthenticatesTo),
            data: %{"granted_privilege" => "administrator"}
          }
        )
      )
    end)
  end

  defp add_mission_capabilities(graph, segment_ids, host_ids, service_ids) do
    [
      %{
        name: "Order processing",
        description: "Public order requests reach the order API.",
        impact_weight: 10.0,
        min_operational_support: 1,
        required_flows: [
          %{
            "source_segment_id" => Map.fetch!(segment_ids, :external),
            "target_service_id" => Map.fetch!(service_ids, {"order-gateway", "https"})
          },
          %{
            "source_segment_id" => Map.fetch!(segment_ids, :public_dmz),
            "target_service_id" => Map.fetch!(service_ids, {"order-service", "order-api"})
          }
        ],
        support_hosts: ["order-service"]
      },
      %{
        name: "Customer support",
        description: "Customer support remains available through either support host.",
        impact_weight: 3.0,
        min_operational_support: 1,
        required_flows: [],
        support_hosts: ["customer-support-service", "admin-service"]
      }
    ]
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {spec, index}, graph ->
      capability =
        Node.new(graph.id, %{
          type: Atom.to_string(MissionCapability),
          data: Map.drop(spec, [:support_hosts]),
          view_data: %{"x_pos" => 1_200, "y_pos" => index * 100}
        })

      graph = Graph.add_node(graph, capability)

      Enum.reduce(spec.support_hosts, graph, fn host_name, graph ->
        Graph.add_edge(
          graph,
          Edge.new(graph.id, Map.fetch!(host_ids, host_name), capability.id, %{
            type: Atom.to_string(Supports),
            data: %{}
          })
        )
      end)
    end)
  end

  defp segment_x(segment) do
    @segments
    |> Enum.find(fn {key, _name, _x_pos} -> key == segment end)
    |> elem(2)
  end

  defp service_version(host, service) do
    case Enum.find(@vulnerabilities, &(&1.host == host and &1.service == service)) do
      nil -> nil
      vulnerability -> vulnerability.version
    end
  end
end
