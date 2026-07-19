defmodule NetworkDefenseWeb.Web.Contracts.GraphContract do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          nodes: [NetworkDefenseWeb.Web.Contracts.Node.t()],
          edges: [NetworkDefenseWeb.Web.Contracts.Edge.t()],
          lock_version: integer()
        }
  defstruct [:id, :title, :nodes, :edges, :lock_version]
end
