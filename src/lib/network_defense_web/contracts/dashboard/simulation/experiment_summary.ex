defmodule NetworkDefenseWeb.Web.Contracts.ExperimentSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :id, :string
    field :graph_id, :string
    field :graph_revision_id, :string
    field :graph_title, :string
    field :seed, :integer
    field :run_count, :integer
    field :iteration_count, :integer
    field :runtime_ms, :integer
    field :started_at, :string
  end

  @type t :: %__MODULE__{
          id: String.t(),
          graph_id: String.t(),
          graph_revision_id: String.t(),
          graph_title: String.t(),
          seed: integer(),
          run_count: integer(),
          iteration_count: integer(),
          runtime_ms: integer(),
          started_at: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :id,
      :graph_id,
      :graph_revision_id,
      :graph_title,
      :seed,
      :run_count,
      :iteration_count,
      :runtime_ms,
      :started_at
    ])
    |> validate_required([
      :id,
      :graph_id,
      :graph_revision_id,
      :graph_title,
      :seed,
      :run_count,
      :iteration_count,
      :runtime_ms,
      :started_at
    ])
  end
end
