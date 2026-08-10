defmodule NetworkDefenseWeb.Web.Contracts.RunOptimizationReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  alias NetworkDefenseWeb.Web.Contracts.DashboardError

  @enum_values status: [:accepted, :rejected]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    field :graph_revision_id, :string
    field :correlation_id, :string
    embeds_one :error, DashboardError, on_replace: :update
  end

  @type t :: %__MODULE__{
          status: String.t(),
          graph_revision_id: String.t(),
          correlation_id: String.t(),
          error: DashboardError.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status, :graph_revision_id, :correlation_id], empty_values: [])
    |> cast_embed(:error)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["accepted", "rejected"])
    |> validate_rejected_error()
  end

  defp validate_rejected_error(changeset) do
    if get_field(changeset, :status) == "rejected" do
      validate_required(changeset, :error)
    else
      changeset
    end
  end
end
