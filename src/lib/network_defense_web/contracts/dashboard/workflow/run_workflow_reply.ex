defmodule NetworkDefenseWeb.Web.Contracts.RunWorkflowReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workflow

  alias NetworkDefenseWeb.Web.Contracts.DashboardError

  @enum_values status: [:accepted, :rejected]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    field :workflow_id, :string
    field :title, :string
    embeds_one :error, DashboardError, on_replace: :update
  end

  @type t :: %__MODULE__{
          status: String.t(),
          workflow_id: String.t() | nil,
          title: String.t() | nil,
          error: DashboardError.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status, :workflow_id, :title], empty_values: [])
    |> cast_embed(:error)
    |> validate_required(:status)
    |> validate_inclusion(:status, ["accepted", "rejected"])
    |> validate_status_fields()
  end

  defp validate_status_fields(changeset) do
    case get_field(changeset, :status) do
      "accepted" -> validate_required(changeset, [:workflow_id, :title])
      "rejected" -> validate_required(changeset, :error)
      _ -> changeset
    end
  end
end
