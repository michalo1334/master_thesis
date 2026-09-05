defmodule NetworkDefenseWeb.Contracts.Dashboard.Runs.RunSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :runs

  @enum_values status: NetworkDefense.Simulation.Experiment.Status.wire_values()
  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :id, :string
    field :kind, :string
    field :title, :string
    field :status, :string
    field :completed, :integer
    field :total, :integer
    field :started_at, :string
  end

  @type t :: %__MODULE__{
          id: String.t(),
          kind: String.t(),
          title: String.t() | nil,
          status: String.t(),
          completed: integer() | nil,
          total: integer() | nil,
          started_at: String.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :kind, :title, :status, :completed, :total, :started_at])
    |> validate_required([:id, :kind, :status])
    |> validate_inclusion(:status, @enum_values[:status])
  end
end
