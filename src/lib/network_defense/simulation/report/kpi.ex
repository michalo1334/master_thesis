defmodule NetworkDefense.Simulation.Report.Kpi do
  @moduledoc false

  @type t :: %__MODULE__{
          label: String.t(),
          value: String.t(),
          detail: String.t(),
          tone: String.t()
        }

  defstruct [:label, :value, :detail, :tone]
end
