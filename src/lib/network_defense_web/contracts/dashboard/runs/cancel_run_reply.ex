defmodule NetworkDefenseWeb.Web.Contracts.CancelRunReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :runs

  @enum_values status: [:cancelled, :not_found, :not_running, :invalid_params]
  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
  end

  @type t :: %__MODULE__{status: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["cancelled", "not_found", "not_running", "invalid_params"])
  end
end
