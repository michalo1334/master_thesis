defmodule NetworkDefense.Workflows.WorkflowRun do
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Workflows.WorkflowStep

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: String.t() | nil,
          title: String.t() | nil,
          template: String.t() | nil,
          correlation_id: String.t() | nil,
          input: map() | nil,
          status: String.t() | nil,
          error: String.t() | nil,
          steps: list() | Ecto.Association.NotLoaded.t()
        }

  schema "workflow_runs" do
    field :title, :string
    field :template, :string
    field :correlation_id, :string
    field :input, :map
    field :status, :string, default: "running"
    field :error, :string

    has_many :steps, WorkflowStep

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:title, :template, :correlation_id, :input, :status, :error])
    |> validate_required([:title, :template, :input, :status])
    |> validate_inclusion(:status, ["running", "completed", "failed"])
    |> unique_constraint([:template, :correlation_id])
  end
end
