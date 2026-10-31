defmodule NetworkDefense.Evaluation2.Study.Definition.Defense do
  @moduledoc false

  use Spectral

  alias NetworkDefense.DefenseActions.Registry, as: DefenseActionsRegistry

  # One study-wide defense policy.
  #
  # The permitted action set applies to every strategy. Each strategy uses the
  # intersection with its own intrinsic capabilities, so no strategy declares a
  # second permission list. One feasibility policy applies to optimization,
  # scoring, and evidence simulation.

  @typedoc """
  Shared feasibility policy. `:required` rejects an infeasible pre-attack
  mission state; `:unrestricted` admits it.
  """
  @type feasibility :: :required | :unrestricted

  @type t :: %__MODULE__{
          feasibility: feasibility(),
          allowed_action_types: [DefenseActionsRegistry.action_type()]
        }
  defstruct [:feasibility, :allowed_action_types]

  @default :required

  @doc "Feasibility policy used when the declaration omits one."
  @spec default() :: feasibility()
  def default, do: @default
end
