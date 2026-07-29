defmodule NetworkDefenseWeb.Web.Contracts.SimulationProgressEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :correlation_id, :string
    field :graph_id, :string
    field :completed_runs, :integer
    field :total_runs, :integer
  end

  @type t :: %__MODULE__{
          correlation_id: String.t(),
          graph_id: String.t(),
          completed_runs: integer(),
          total_runs: integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:correlation_id, :graph_id, :completed_runs, :total_runs])
    |> validate_required([:correlation_id, :graph_id, :completed_runs, :total_runs])
    |> validate_number(:completed_runs, greater_than: 0)
    |> validate_number(:total_runs, greater_than: 0)
  end
end
