defmodule NetworkDefenseWeb.Web.Contracts.KpiMetric do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          label: String.t(),
          value: String.t(),
          detail: String.t(),
          tone: String.t()
        }
  defstruct [:label, :value, :detail, :tone]
end
