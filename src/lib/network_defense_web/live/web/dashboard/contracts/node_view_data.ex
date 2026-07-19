defmodule NetworkDefenseWeb.Web.Contracts.NodeViewData do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          x_pos: float(),
          y_pos: float(),
          radius: float() | nil
        }
  defstruct [:x_pos, :y_pos, :radius]
end
