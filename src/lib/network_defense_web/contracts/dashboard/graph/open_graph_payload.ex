defmodule NetworkDefenseWeb.Web.Contracts.OpenGraphPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts

  embedded_schema do
    field :graph_id, :string
  end

  @type t :: %__MODULE__{
          graph_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_id])
    |> validate_required([:graph_id])
    |> validate_length(:graph_id, min: 1)
    |> validate_uuid(:graph_id)
  end

  defp validate_uuid(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _uuid} -> []
        :error -> [{field, "is invalid"}]
      end
    end)
  end
end
