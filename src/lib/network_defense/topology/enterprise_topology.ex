defmodule NetworkDefense.Topology.EnterpriseTopology do
  @moduledoc """
  Pure deterministic generator of a segmented enterprise topology graph.

  The graph is deny-by-default: the only reachability edges added are the fixed
  rules below. Hosts are grouped into zones (dmz, internal, restricted,
  management, workstations) plus a single `internet` ingress node that is not
  counted in `:hosts`. Extra hosts beyond the base set get their role from a
  seeded first-order Markov chain over roles.

  Reachability rules:

    * internet -> DMZ public HTTPS (443)
    * DMZ -> internal API (8080)
    * internal applications -> restricted PostgreSQL (5432)
    * workstations -> restricted LDAP (389) / SMB (445)
    * management bastions -> SSH (22) on server hosts

  Topology structure is a pure function of `(title, hosts, seed)`.
  """

  alias NetworkDefense.Graph.{Edge, Graph, Node}
  alias NetworkDefense.Nodes.{Host, NetworkSegment, Service, Vulnerability}
  alias NetworkDefense.Relationships.{Contains, HasVulnerability, NetworkReachability, Runs}
  alias NetworkDefense.Simulation.Seed
  alias NetworkDefense.Topology.VulnerabilityCatalog

  @minimum_hosts 8

  @base_roles [
    :dmz_web,
    :internal_api,
    :internal_app,
    :restricted_db,
    :restricted_ad,
    :mgmt_bastion,
    :workstation
  ]

  @initial_role :workstation

  @roles %{
    dmz_web: %{
      zone: :dmz,
      prefix: "dmz-web",
      services: [{"https", "tcp", 443, "nginx 1.25"}, {"ssh", "tcp", 22, "openssh 9.6"}]
    },
    internal_api: %{
      zone: :internal,
      prefix: "internal-api",
      services: [{"api", "tcp", 8080, "gunicorn 21"}, {"ssh", "tcp", 22, "openssh 9.6"}]
    },
    internal_app: %{
      zone: :internal,
      prefix: "internal-app",
      services: [{"app", "tcp", 8081, "spring-boot 3.2"}, {"ssh", "tcp", 22, "openssh 9.6"}]
    },
    restricted_db: %{
      zone: :restricted,
      prefix: "restricted-db",
      services: [
        {"postgresql", "tcp", 5432, "postgresql 15.4"},
        {"ssh", "tcp", 22, "openssh 9.6"}
      ]
    },
    restricted_ad: %{
      zone: :restricted,
      prefix: "restricted-ad",
      services: [
        {"ldap", "tcp", 389, "openldap 2.6"},
        {"smb", "tcp", 445, "samba 4.18"},
        {"ssh", "tcp", 22, "openssh 9.6"}
      ]
    },
    mgmt_bastion: %{
      zone: :mgmt,
      prefix: "mgmt-bastion",
      services: [{"ssh", "tcp", 22, "openssh 9.6"}]
    },
    workstation: %{zone: :workstation, prefix: "workstation", services: []}
  }

  @transitions %{
    dmz_web: [{:internal_api, 1}],
    internal_api: [{:internal_app, 2}, {:restricted_db, 1}],
    internal_app: [{:restricted_db, 2}, {:internal_app, 1}, {:workstation, 1}],
    restricted_db: [{:restricted_ad, 1}, {:internal_app, 1}],
    restricted_ad: [{:workstation, 2}, {:mgmt_bastion, 1}],
    mgmt_bastion: [{:internal_api, 2}, {:dmz_web, 1}, {:mgmt_bastion, 1}],
    workstation: [{:workstation, 2}, {:internal_app, 1}, {:dmz_web, 1}]
  }

  @zone_columns %{
    external: 0,
    dmz: 100,
    internal: 300,
    restricted: 500,
    mgmt: 700,
    workstation: 900
  }

  @segments [
    {:external, "External"},
    {:dmz, "DMZ"},
    {:internal, "Internal"},
    {:restricted, "Restricted"},
    {:mgmt, "Management"},
    {:workstation, "Workstations"}
  ]

  @server_roles [:dmz_web, :internal_api, :internal_app, :restricted_db, :restricted_ad]

  @doc "Minimum number of enterprise hosts required to cover all zones and roles."
  def minimum_hosts, do: @minimum_hosts

  @doc """
  Generates a topology graph.

  Options:

    * `:title` - graph title (default `"Enterprise topology"`)
    * `:hosts` - number of enterprise hosts, at least `#{@minimum_hosts}` (default `#{@minimum_hosts}`)
    * `:seed` - deterministic seed (default `0`)

  Raises `ArgumentError` for invalid options.
  """
  def generate(opts \\ []) do
    title = Keyword.get(opts, :title, "Enterprise topology")
    host_count = Keyword.get(opts, :hosts, @minimum_hosts)
    seed = Keyword.get(opts, :seed, Seed.default())

    validate_title!(title)

    if not is_integer(host_count) or host_count < @minimum_hosts do
      raise ArgumentError,
            "hosts must be an integer >= #{@minimum_hosts}, got: #{inspect(host_count)}"
    end

    if not is_integer(seed) do
      raise ArgumentError, "seed must be an integer, got: #{inspect(seed)}"
    end

    state = Seed.integer_to_state(seed)
    {roles, _state} = select_roles(host_count, state)

    graph = Graph.new(title)
    {graph, internet_id} = add_internet_node(graph)

    {graph, hosts_by_role, _vulnerabilities} =
      Enum.reduce(roles, {graph, %{}, %{}}, fn {role, index}, {graph, by_role, vulnerabilities} ->
        {host_id, services, graph, vulnerabilities} =
          build_role_host(graph, role, index, vulnerabilities)

        {graph, Map.update(by_role, role, [{host_id, services}], &[{host_id, services} | &1]),
         vulnerabilities}
      end)

    graph
    |> add_segments(internet_id, hosts_by_role)
    |> add_reachability(internet_id, hosts_by_role)
  end

  defp add_internet_node(graph) do
    internet =
      Node.new(graph.id, %{
        type: Atom.to_string(Host),
        data: %{"name" => "internet"},
        view_data: %{"x_pos" => 0, "y_pos" => 0}
      })

    {Graph.add_node(graph, internet), internet.id}
  end

  defp add_segments(graph, internet_id, hosts_by_role) do
    Enum.reduce(@segments, graph, fn {zone, name}, graph ->
      segment =
        Node.new(graph.id, %{
          type: Atom.to_string(NetworkSegment),
          data: %{"name" => name},
          view_data: segment_position(zone)
        })

      graph = Graph.add_node(graph, segment)

      Enum.reduce(host_ids_for_zone(zone, internet_id, hosts_by_role), graph, fn host_id, graph ->
        Graph.add_edge(
          graph,
          Edge.new(graph.id, segment.id, host_id, %{type: Atom.to_string(Contains), data: %{}})
        )
      end)
    end)
  end

  defp host_ids_for_zone(:external, internet_id, _hosts_by_role), do: [internet_id]

  defp host_ids_for_zone(zone, _internet_id, hosts_by_role) do
    for {role, hosts} <- Enum.sort_by(hosts_by_role, &elem(&1, 0)),
        Map.fetch!(@roles, role).zone == zone,
        {host_id, _services} <- hosts,
        do: host_id
  end

  defp build_role_host(graph, role, index, vulnerabilities) do
    %{zone: zone, prefix: prefix, services: service_specs} = Map.fetch!(@roles, role)
    name = "#{prefix}-#{index}"

    host =
      Node.new(graph.id, %{
        type: Atom.to_string(Host),
        data: %{"name" => name},
        view_data: host_position(zone, index)
      })

    graph = Graph.add_node(graph, host)

    {services, graph, vulnerabilities} =
      service_specs
      |> Enum.with_index()
      |> Enum.reduce({%{}, graph, vulnerabilities}, fn {spec, service_index},
                                                       {services, graph, vulnerabilities} ->
        layout = %{zone: zone, index: index, service_index: service_index}
        add_service(graph, host.id, spec, layout, services, vulnerabilities)
      end)

    {host.id, services, graph, vulnerabilities}
  end

  defp add_service(
         graph,
         host_id,
         {name, protocol, port, version},
         layout,
         services,
         vulnerabilities
       ) do
    service =
      Node.new(graph.id, %{
        type: Atom.to_string(Service),
        data: %{"name" => name, "protocol" => protocol, "port" => port, "version" => version},
        view_data: service_position(layout)
      })

    graph = Graph.add_node(graph, service)
    graph = add_runs_edge(graph, host_id, service.id)

    {graph, vulnerabilities} =
      VulnerabilityCatalog.for_service(%{name: name, version: version})
      |> Enum.with_index()
      |> Enum.reduce({graph, vulnerabilities}, fn {vuln, vuln_index}, {graph, vulnerabilities} ->
        {vulnerability_id, graph, vulnerabilities} =
          ensure_vulnerability(graph, vulnerabilities, vuln, layout, vuln_index)

        {add_vulnerability_edge(graph, service.id, vulnerability_id), vulnerabilities}
      end)

    {Map.put(services, name, service.id), graph, vulnerabilities}
  end

  defp add_runs_edge(graph, host_id, service_id) do
    Graph.add_edge(
      graph,
      Edge.new(graph.id, host_id, service_id, %{
        type: Atom.to_string(Runs),
        data: %{}
      })
    )
  end

  defp ensure_vulnerability(graph, vulnerabilities, vuln, layout, vuln_index) do
    case Map.fetch(vulnerabilities, vuln.identifier) do
      {:ok, vulnerability_id} ->
        {vulnerability_id, graph, vulnerabilities}

      :error ->
        vuln_node =
          Node.new(graph.id, %{
            type: Atom.to_string(Vulnerability),
            data: %{
              "identifier" => vuln.identifier,
              "cvss" => vuln.cvss,
              "exploit_probability" => vuln.exploit_probability
            },
            view_data: vuln_position(layout, vuln_index)
          })

        {vuln_node.id, Graph.add_node(graph, vuln_node),
         Map.put(vulnerabilities, vuln.identifier, vuln_node.id)}
    end
  end

  defp add_vulnerability_edge(graph, service_id, vulnerability_id) do
    Graph.add_edge(
      graph,
      Edge.new(graph.id, service_id, vulnerability_id, %{
        type: Atom.to_string(HasVulnerability),
        data: %{"required_privilege" => "none", "granted_privilege" => "user"}
      })
    )
  end

  defp add_reachability(graph, internet_id, hosts_by_role) do
    pairs =
      internet_https_pairs(internet_id, Map.get(hosts_by_role, :dmz_web, [])) ++
        dmz_api_pairs(
          Map.get(hosts_by_role, :dmz_web, []),
          Map.get(hosts_by_role, :internal_api, [])
        ) ++
        app_db_pairs(
          Map.get(hosts_by_role, :internal_api, []) ++ Map.get(hosts_by_role, :internal_app, []),
          Map.get(hosts_by_role, :restricted_db, [])
        ) ++
        workstation_ad_pairs(
          Map.get(hosts_by_role, :workstation, []),
          Map.get(hosts_by_role, :restricted_ad, [])
        ) ++ bastion_ssh_pairs(Map.get(hosts_by_role, :mgmt_bastion, []), hosts_by_role)

    Enum.reduce(pairs, graph, fn {from, to, port}, graph ->
      add_reachability_edge(graph, from, to, port)
    end)
  end

  defp internet_https_pairs(internet_id, dmz_hosts),
    do: for({_host, services} <- dmz_hosts, do: {internet_id, Map.fetch!(services, "https"), 443})

  defp dmz_api_pairs(dmz_hosts, api_hosts),
    do:
      for(
        {dmz, _services} <- dmz_hosts,
        {_host, services} <- api_hosts,
        do: {dmz, Map.fetch!(services, "api"), 8080}
      )

  defp app_db_pairs(app_hosts, db_hosts),
    do:
      for(
        {app, _services} <- app_hosts,
        {_host, services} <- db_hosts,
        do: {app, Map.fetch!(services, "postgresql"), 5432}
      )

  defp workstation_ad_pairs(workstation_hosts, ad_hosts) do
    ldap =
      for(
        {workstation, _services} <- workstation_hosts,
        {_host, services} <- ad_hosts,
        do: {workstation, Map.fetch!(services, "ldap"), 389}
      )

    smb =
      for(
        {workstation, _services} <- workstation_hosts,
        {_host, services} <- ad_hosts,
        do: {workstation, Map.fetch!(services, "smb"), 445}
      )

    ldap ++ smb
  end

  defp bastion_ssh_pairs(bastion_hosts, hosts_by_role),
    do:
      for(
        {bastion, _services} <- bastion_hosts,
        role <- @server_roles,
        {_host, services} <- Map.get(hosts_by_role, role, []),
        do: {bastion, Map.fetch!(services, "ssh"), 22}
      )

  defp add_reachability_edge(graph, from_id, to_id, port) do
    Graph.add_edge(
      graph,
      Edge.new(graph.id, from_id, to_id, %{
        type: Atom.to_string(NetworkReachability),
        data: %{"protocol" => "tcp", "port_start" => port, "port_end" => port}
      })
    )
  end

  defp select_roles(host_count, state) do
    extra_count = host_count - length(@base_roles)
    {extras, state} = pick_extra_roles(extra_count, state, @initial_role)
    {index_roles(@base_roles ++ extras), state}
  end

  defp pick_extra_roles(0, state, _last), do: {[], state}

  defp pick_extra_roles(count, state, last) do
    {role, state} = next_role(state, last)
    {rest, state} = pick_extra_roles(count - 1, state, role)
    {[role | rest], state}
  end

  defp next_role(state, role) do
    transitions = Map.fetch!(@transitions, role)
    total = Enum.reduce(transitions, 0, fn {_candidate, weight}, acc -> acc + weight end)
    {roll, state} = :rand.uniform_s(total, state)
    {pick_transition(transitions, roll), state}
  end

  defp pick_transition([{candidate, weight} | rest], roll) do
    if roll <= weight, do: candidate, else: pick_transition(rest, roll - weight)
  end

  defp index_roles(roles) do
    {indexed, _counters} =
      Enum.map_reduce(roles, %{}, fn role, counters ->
        index = Map.get(counters, role, 0) + 1
        {{role, index}, Map.put(counters, role, index)}
      end)

    indexed
  end

  defp validate_title!(title) when is_binary(title) do
    if String.length(title) in 1..255 do
      :ok
    else
      raise ArgumentError, "title must be between 1 and 255 characters, got: #{inspect(title)}"
    end
  end

  defp validate_title!(title),
    do: raise(ArgumentError, "title must be between 1 and 255 characters, got: #{inspect(title)}")

  defp host_position(zone, index),
    do: %{"x_pos" => Map.fetch!(@zone_columns, zone), "y_pos" => index * 120}

  defp segment_position(:external),
    do: %{"x_pos" => Map.fetch!(@zone_columns, :external), "y_pos" => -100}

  defp segment_position(zone), do: %{"x_pos" => Map.fetch!(@zone_columns, zone), "y_pos" => 0}

  defp service_position(%{zone: zone, index: index, service_index: service_index}),
    do: %{
      "x_pos" => Map.fetch!(@zone_columns, zone) + 70,
      "y_pos" => index * 120 - 30 + service_index * 40
    }

  defp vuln_position(%{zone: zone, index: index, service_index: service_index}, vuln_index),
    do: %{
      "x_pos" => Map.fetch!(@zone_columns, zone) + 140,
      "y_pos" => index * 120 - 60 + service_index * 40 + vuln_index * 40
    }
end
