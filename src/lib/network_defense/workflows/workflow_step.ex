defmodule NetworkDefense.Workflows.WorkflowStep do
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Workflows.WorkflowRun

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workflow_steps" do
    belongs_to :workflow_run, WorkflowRun

    field :position, :integer
    field :name, :string
    field :status, :string, default: "pending"
    field :resource_id, :string
    field :output, :map
    field :error, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(step, attrs) do
    step
    |> cast(attrs, [:workflow_run_id, :position, :name, :status, :resource_id, :output, :error])
    |> validate_required([:workflow_run_id, :position, :name, :status])
    |> validate_number(:position, greater_than: 0)
    |> validate_inclusion(:status, ["pending", "running", "completed", "failed"])
    |> foreign_key_constraint(:workflow_run_id)
    |> unique_constraint([:workflow_run_id, :position])
    |> unique_constraint([:workflow_run_id, :name])
  end
end
