defmodule Mix.Tasks.Generate.EnterpriseTopology do
  use Mix.Task

  @moduledoc """
  Generates a deterministic, deny-by-default enterprise topology and persists it
  as a new graph revision.

      mix generate.enterprise_topology --title "Acme Corp" --hosts 12 --seed 42

  Options:

    * `--title` - graph title (default `"Enterprise topology"`)
    * `--hosts` - enterprise host count, at least
      `#{NetworkDefense.Topology.EnterpriseTopology.minimum_hosts()}` (default
      `#{NetworkDefense.Topology.EnterpriseTopology.minimum_hosts()}`)
    * `--seed` - deterministic seed (default `0`)
  """

  @shortdoc "Generate and persist a deterministic enterprise topology graph"

  @requirements ["app.start"]

  @switches [title: :string, hosts: :integer, seed: :integer]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if positional != [] or invalid != [] do
      invalid_options = Enum.map(invalid, fn {option, _value} -> option end)
      Mix.raise("invalid options: #{Enum.join(positional ++ invalid_options, ", ")}")
    end

    graph =
      try do
        NetworkDefense.Topology.EnterpriseTopology.generate(
          title: Keyword.get(opts, :title, "Enterprise topology"),
          hosts:
            Keyword.get(opts, :hosts, NetworkDefense.Topology.EnterpriseTopology.minimum_hosts()),
          seed: Keyword.get(opts, :seed, 0)
        )
      rescue
        error in ArgumentError -> Mix.raise(error.message)
      end

    case NetworkDefense.Graph.Graphs.insert(graph) do
      {:ok, persisted} ->
        IO.puts(
          "persisted '#{persisted.title}' " <>
            "(revision #{persisted.revision_id}, #{length(NetworkDefense.Graph.Graph.nodes(persisted))} " <>
            "nodes, #{length(NetworkDefense.Graph.Graph.edges(persisted))} edges)"
        )

      {:error, reason} ->
        Mix.raise("failed to persist enterprise topology: #{inspect(reason)}")
    end
  end
end
