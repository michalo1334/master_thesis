defmodule NetworkDefenseWeb.Web.Contracts.EvaluationPlanSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :id, :string
    field :strategy, :string
    field :requested_budget, :integer
    field :selection_seed, :integer
    field :used_budget, :integer
    field :action_count, :integer
    field :status, :string
  end

  @type t :: %__MODULE__{
          id: String.t(),
          strategy: String.t(),
          requested_budget: integer(),
          selection_seed: integer(),
          used_budget: integer(),
          action_count: integer(),
          status: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :id,
      :strategy,
      :requested_budget,
      :selection_seed,
      :used_budget,
      :action_count,
      :status
    ])
    |> validate_required([:id, :strategy, :requested_budget, :selection_seed, :status])
    |> NetworkDefense.Contracts.validate_uuid(:id)
    |> validate_inclusion(:status, ["running", "completed", "failed"])
  end
end
