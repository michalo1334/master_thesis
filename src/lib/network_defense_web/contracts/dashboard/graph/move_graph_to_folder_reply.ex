defmodule NetworkDefenseWeb.Web.Contracts.MoveGraphToFolderReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @enum_values status: [
                 :ok,
                 :not_found,
                 :invalid_graph,
                 :invalid_folder,
                 :folder_not_found,
                 :unmapped_error
               ]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
  end

  @type t :: %__MODULE__{status: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, [
      "ok",
      "not_found",
      "invalid_graph",
      "invalid_folder",
      "folder_not_found",
      "unmapped_error"
    ])
  end
end
