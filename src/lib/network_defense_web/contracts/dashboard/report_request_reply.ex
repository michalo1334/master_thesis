defmodule NetworkDefenseWeb.Contracts.Dashboard.ReportRequestReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  @enum_values status: [:processing, :unavailable, :invalid_params]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
  end

  @type t :: %__MODULE__{status: String.t()}

  def changeset(schema, attrs), do: Contracts.report_request_changeset(schema, attrs)
end
