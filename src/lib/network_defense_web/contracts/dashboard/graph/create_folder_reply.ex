defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.CreateFolderReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @enum_values status: [:ok, :invalid_folder, :unmapped_error]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string

    embeds_one :folder, NetworkDefenseWeb.Contracts.Dashboard.Graph.FolderSummary,
      on_replace: :update
  end

  @type t :: %__MODULE__{
          status: String.t(),
          folder: NetworkDefenseWeb.Contracts.Dashboard.Graph.FolderSummary.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:folder)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "invalid_folder", "unmapped_error"])
  end
end
