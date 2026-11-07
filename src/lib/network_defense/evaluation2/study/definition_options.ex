defmodule NetworkDefense.Evaluation2.Study.DefinitionOptions do
  @moduledoc """
  Authoring options of one new study revision.

  Every list comes from the registry that owns the value and keeps its registry
  order. The values are wire identifiers, because presentation labels belong to
  the browser. The options describe the current application, so a frozen
  revision does not own them.

  `measurement_label` is the configured environment label that creation would
  freeze now. A nil label means that Final measured collection is unavailable
  until the environment declares one.
  """

  use Spectral

  alias NetworkDefense.Evaluation2.Study.StrategyOption

  @type t :: %__MODULE__{
          actions: [String.t()],
          rules: [String.t()],
          alternatives: [StrategyOption.t()],
          objectives: [String.t()],
          measurement_label: String.t() | nil
        }

  defstruct [:actions, :rules, :alternatives, :objectives, :measurement_label]
end
