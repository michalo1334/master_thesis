defmodule NetworkDefense.Simulation.Report.Chart do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          takeaway: String.t(),
          aria_label: String.t(),
          option: map()
        }

  defstruct [:id, :title, :takeaway, :aria_label, :option]
end
