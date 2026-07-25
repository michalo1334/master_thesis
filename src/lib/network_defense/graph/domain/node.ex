defmodule NetworkDefense.Graph.Domain.Node do
  @moduledoc false

  alias NetworkDefense.Graph.Domain.ViewData

  @enforce_keys [:id, :graph_id, :type, :data, :view_data]
  defstruct [:id, :graph_id, :type, :data, :view_data]

  @type t :: %__MODULE__{
          id: String.t(),
          graph_id: String.t(),
          type: module(),
          data: struct(),
          view_data: ViewData.t()
        }
end
