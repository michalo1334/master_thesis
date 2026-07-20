defmodule NetworkDefenseWeb.Web.Contracts.ChartSpec do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          takeaway: String.t(),
          aria_label: String.t(),
          option: map()
        }
  defstruct [:id, :title, :takeaway, :aria_label, :option]
end
