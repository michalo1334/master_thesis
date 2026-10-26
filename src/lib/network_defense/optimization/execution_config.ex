defmodule NetworkDefense.Optimization.ExecutionConfig do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.DefenseActions.Registry, as: DefenseActionsRegistry
  alias NetworkDefense.Optimization.Contracts.SimulationSettings

  @primary_key false

  embedded_schema do
    field :candidate_action_types, {:array, Ecto.Enum}, values: DefenseActionsRegistry.values()

    field :require_pre_attack_feasibility, :boolean
    field :initial_foothold_node_id, :string
    embeds_one :scoring, SimulationSettings, on_replace: :update
  end

  @type t :: %__MODULE__{
          candidate_action_types: [DefenseActionsRegistry.action_type()],
          require_pre_attack_feasibility: boolean(),
          initial_foothold_node_id: String.t() | nil,
          scoring: SimulationSettings.t() | nil
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :candidate_action_types,
      :require_pre_attack_feasibility,
      :initial_foothold_node_id
    ])
    |> cast_embed(:scoring)
    |> validate_required([:candidate_action_types, :require_pre_attack_feasibility])
    |> validate_length(:candidate_action_types, min: 1)
  end
end
