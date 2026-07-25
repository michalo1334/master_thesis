defmodule NetworkDefense.Graph.Domain.Edge do
  @moduledoc false

  @enforce_keys [:id, :graph_id, :from_id, :to_id, :type, :data]
  defstruct [:id, :graph_id, :from_id, :to_id, :type, :data]

  @type t :: %__MODULE__{
          id: String.t(),
          graph_id: String.t(),
          from_id: String.t(),
          to_id: String.t(),
          type: module(),
          data: struct()
        }
end
