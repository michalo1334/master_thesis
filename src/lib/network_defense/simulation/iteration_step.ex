defmodule NetworkDefense.Simulation.IterationStep do
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Actions.AttemptedAction
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Simulation.Run

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          run_id: String.t() | nil,
          index: non_neg_integer(),
          attempted_action: AttemptedAction.t() | nil,
          success?: boolean(),
          attacker_state: AttackerState.t()
        }

  schema "iteration_steps" do
    belongs_to :run, Run

    field :index, :integer
    field :success?, :boolean, source: :success
    embeds_one :attempted_action, AttemptedAction, on_replace: :update
    embeds_one :attacker_state, AttackerState, on_replace: :update

    timestamps(type: :utc_datetime)
  end

  def changeset(step, attrs) do
    changeset =
      step
      |> cast(attrs, [:index, :success?])

    changeset =
      changeset
      |> put_embedded(:attempted_action, Map.get(attrs, :attempted_action))
      |> put_embedded(:attacker_state, Map.get(attrs, :attacker_state))

    changeset
    |> validate_required([:run_id, :index, :success?])
    |> validate_number(:index, greater_than: 0)
    |> foreign_key_constraint(:run_id)
    |> unique_constraint([:run_id, :index])
  end

  def new(attrs), do: struct!(__MODULE__, Map.put(Map.new(attrs), :id, Ecto.UUID.generate()))

  defp put_embedded(changeset, _field, nil), do: changeset
  defp put_embedded(changeset, field, value), do: put_embed(changeset, field, value)
end
