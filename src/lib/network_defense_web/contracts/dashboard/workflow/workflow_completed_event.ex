defmodule NetworkDefenseWeb.Web.Contracts.WorkflowCompletedEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workflow

  embedded_schema do
    field :workflow_id, :string
    field :baseline_experiment_id, :string
    field :optimization_id, :string
    field :output_graph_revision_id, :string
    field :after_experiment_id, :string
  end

  @type t :: %__MODULE__{
          workflow_id: String.t(),
          baseline_experiment_id: String.t(),
          optimization_id: String.t(),
          output_graph_revision_id: String.t(),
          after_experiment_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :workflow_id,
      :baseline_experiment_id,
      :optimization_id,
      :output_graph_revision_id,
      :after_experiment_id
    ])
    |> validate_required([
      :workflow_id,
      :baseline_experiment_id,
      :optimization_id,
      :output_graph_revision_id,
      :after_experiment_id
    ])
  end
end
