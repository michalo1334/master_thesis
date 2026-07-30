defmodule NetworkDefense.Optimization.CvssStrategy do
  @moduledoc false

  alias NetworkDefense.Cvss
  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Optimization.{Budget, Strategy}
  alias NetworkDefense.Relationships.HasVulnerability

  defstruct []

  def new(_graph, _params), do: {:ok, %__MODULE__{}}

  defimpl Strategy, for: __MODULE__ do
    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "CVSS strategy"

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: list()
    def rank(_strategy, action_types, graph, _budget) do
      if PatchVulnerability in action_types do
        graph
        |> Graph.edges()
        |> Enum.filter(&(&1.type == HasVulnerability))
        |> Enum.sort_by(fn edge ->
          vulnerability = Graph.node(graph, edge.to_id)
          {-Cvss.base_score(vulnerability.data.cvss), edge.id}
        end)
        |> Enum.map(&%PatchVulnerability{edge_id: &1.id})
      else
        []
      end
    end
  end
end
