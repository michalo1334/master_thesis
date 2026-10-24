defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.PilotToFinal do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # The handoff from Pilot to Final.
  #
  # Only `pause` exists. Final evidence collection may not start from a Pilot
  # completion event, because the measured candidate must be reviewed before
  # new plans and new seeds are spent.

  @type t :: %__MODULE__{mode: String.t()}

  embedded_schema do
    field :mode, :string
  end

  def changeset(handoff, attrs) do
    handoff
    |> cast(attrs, [:mode])
    |> validate_required([:mode])
  end
end
